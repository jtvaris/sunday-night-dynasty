import SwiftUI

// MARK: - Preseason recap — the tape, and the case each man made
//
// `docs/OFFSEASON_ROSTER_PLAN.md` §5 (spec item 4) and R10. A preseason game is
// sim-only, so the ONLY thing it can be worth to the user is evidence: the 75 →
// 65 → 53 ladder is decided on these stat lines, and if the recap does not make
// the case for and against each bubble man then three preseason games really
// are three taps.
//
// So this file carries three things, in the order the screen uses them:
//
//   1. `PreseasonCampCase` — the verdict machine. Given a stat line, did this
//      man help his case, hold his ground, hurt himself, or not factor?
//   2. `PreseasonRecap` — the view model. Built ONCE, in one initializer, from
//      the engine's `PreseasonResult`. That initializer is the single point
//      where this UI touches `PreseasonEngine`'s payload shape.
//   3. `PreseasonRecapSheet` (the §2.6 ending) and `PreseasonBubbleTable` (the
//      evidence behind it).
//
// **Why the table is not inside the sheet.** `DSResultSheet`'s contract is
// headline → what changed → what it cost → one commit. A scrollable 30-row
// table inside it breaks that shape and re-opens §2.6's ban on in-place body
// swaps. The plan's answer, followed here: the sheet carries four chips and the
// price of the policy; the full table renders on `PreseasonView` *behind* the
// sheet and is revealed by Continue. The user leaves the modal into the
// evidence, not away from it.
//
// **Fog does not apply here.** Invariant (5) governs *scouted* values on men the
// club does not own. These are the user's own players' own box scores from his
// own game: they are true, and printing them as bands would be a lie in the
// other direction.

// MARK: - The verdict machine

/// How a preseason outing is DISPLAYED — the pill word, the tone, the sentence
/// VoiceOver reads.
///
/// **The verdict itself is not decided here.** It is decided in
/// `PreseasonEngine.CampCase`, off the real box score against a positional
/// expectation, and this type is the presentation vocabulary over it. That
/// split is #208 FIX C: the thresholds used to live in this file, as absolute
/// fantasy-shaped points behind a three-involvement volume floor, and they
/// classified an entire camp roster as `quiet` in every game of the QA slate —
/// a scoring rule that cannot see a one-target touchdown is not a scoring rule
/// for a cutdown. One authority now answers "did he move", and it is the engine
/// that also knows how the snaps were handed out.
enum PreseasonCampCase {

    /// What the tape said. Mirrors `PreseasonEngine.CampCase.Verdict` one for
    /// one; the mapping below is the only place the two meet.
    enum Verdict: String, CaseIterable {
        /// Played himself closer to the 53.
        case helped
        /// Did his job. Nothing moved.
        case held
        /// Played himself further from it.
        case hurt
        /// Dressed, barely featured. The box score has nothing to say.
        case quiet

        /// The pill ident. Short by house rule — §2.2's clipping defect is a
        /// long word in a fixed column.
        ///
        /// `hurt` prints "Slipped", not "Hurt": the same rows carry a real
        /// injury glyph and the sheet above them carries an INJURIES chip, so a
        /// red "HURT" pill beside "none among the ones" read as a medical
        /// status. The column is headed CASE and the pill now speaks its
        /// vocabulary.
        var pillLabel: String {
            switch self {
            case .helped: return "Helped"
            case .held:   return "Held"
            case .hurt:   return "Slipped"
            case .quiet:  return "Quiet"
            }
        }

        /// The sentence the row means, for VoiceOver and for the sheet's prose.
        var spoken: String {
            switch self {
            case .helped: return "helped his case"
            case .held:   return "held his ground"
            case .hurt:   return "hurt his case"
            case .quiet:  return "did not factor"
            }
        }

        var tone: DSStatusPill.Tone {
            switch self {
            case .helped: return .ok
            case .held:   return .neutral
            case .hurt:   return .bad
            case .quiet:  return .empty
            }
        }

        init(_ engine: PreseasonEngine.CampCase.Verdict) {
            switch engine {
            case .helped: self = .helped
            case .held:   self = .held
            case .hurt:   self = .hurt
            case .quiet:  self = .quiet
            }
        }

        var moved: Bool { self == .helped || self == .hurt }
    }

    // MARK: Standout ranking
    //
    // The one judgement this file still makes on its own, because it is a
    // presentation question rather than a football one: of the men who helped
    // themselves, whose afternoon does the SHEET lead with.

    /// Established starters are discounted when the sheet picks the game's
    /// standout: the recap exists to surface the men whose roster spot is in
    /// question, and a starter's good day was expected.
    static let starterStandoutDiscount = 0.5
    /// …and a rookie's good day is the one the cutdown most wants to see.
    static let rookieStandoutBoost = 1.15

    /// The engine's read of one stat line — verdict, case points and the line
    /// of evidence, in one call so the three can never disagree.
    static func read(_ s: PlayerGameStats) -> PreseasonEngine.CampCase.Read {
        PreseasonEngine.CampCase.read(s)
    }

    /// The one-line box score, in the club's own shorthand.
    ///
    /// At most three segments, longest-first, so a running back who caught four
    /// balls gets both halves of his day and a linebacker does not get a line
    /// full of zeroes.
    static func statLine(_ s: PlayerGameStats) -> String {
        var parts: [String] = []

        if s.attempts > 0 {
            var passing = "\(s.completions)/\(s.attempts), \(s.passingYards) yds"
            if s.passingTDs > 0 { passing += ", \(s.passingTDs) TD" }
            if s.interceptions > 0 { passing += ", \(s.interceptions) INT" }
            parts.append(passing)
        }
        if s.carries > 0 {
            var rushing = "\(s.carries) car, \(s.rushingYards) yds"
            if s.rushingTDs > 0 { rushing += ", \(s.rushingTDs) TD" }
            parts.append(rushing)
        }
        if s.targets > 0 || s.receptions > 0 {
            var receiving = "\(s.receptions)/\(s.targets) rec, \(s.receivingYards) yds"
            if s.receivingTDs > 0 { receiving += ", \(s.receivingTDs) TD" }
            parts.append(receiving)
        }
        if s.tackles > 0 || s.sacks > 0 || s.interceptionsCaught > 0
            || s.forcedFumbles > 0 || s.passDeflectionCount > 0 {
            var defence: [String] = []
            if s.tackles > 0 { defence.append("\(s.tackles) tkl") }
            if s.sacks > 0 { defence.append(String(format: "%.1f sk", s.sacks)) }
            if s.interceptionsCaught > 0 { defence.append("\(s.interceptionsCaught) INT") }
            if s.forcedFumbles > 0 { defence.append("\(s.forcedFumbles) FF") }
            if s.passDeflectionCount > 0 { defence.append("\(s.passDeflectionCount) PD") }
            parts.append(defence.joined(separator: ", "))
        }
        if s.fieldGoalsAttempted > 0 {
            parts.append("\(s.fieldGoalsMade)/\(s.fieldGoalsAttempted) FG")
        }

        guard !parts.isEmpty else { return "No stat line" }
        return parts.prefix(3).joined(separator: " \u{00B7} ")
    }
}

// MARK: - The view model

/// One preseason game, as the recap sheet and the evidence table need it.
///
/// Built once per game, in `init(result:…)` below — the ONE place this UI reads
/// `PreseasonResult`'s shape.
struct PreseasonRecap: Identifiable {

    /// Where a man stands on the roster, which is the whole reason the recap
    /// exists: the cut ladder is about everyone who is not a starter.
    enum Tier {
        /// Signed to fill the camp roster (`RosterStatus.campBody`).
        case campBody
        /// First year in the league.
        case rookie
        /// On the roster, not in the projected starting lineup.
        case bubble
        /// In the projected starting lineup.
        case starter

        var pillLabel: String {
            switch self {
            case .campBody: return "Camp"
            case .rookie:   return "Rook"
            case .bubble:   return "Bubble"
            case .starter:  return "Starter"
            }
        }

        var tone: DSStatusPill.Tone {
            switch self {
            case .campBody: return .neutral
            case .rookie:   return .info
            case .bubble:   return .warn
            case .starter:  return .ok
            }
        }

        /// Everyone whose spot the 75 → 65 → 53 ladder actually threatens.
        var isCutCohort: Bool { self != .starter }
    }

    struct Line: Identifiable {
        let id: UUID
        let name: String
        let position: Position
        let overall: Int
        /// Age and years left on the deal. An exhibition box score says what a
        /// man did on one afternoon; these two say what releasing him costs,
        /// and the screen that writes the cut to 65 had neither anywhere on it
        /// nor one tap away.
        let age: Int
        let contractYears: Int
        let tier: Tier
        let isRookie: Bool
        let statLine: String
        /// Production minus what the position asks of a man with that many
        /// chances (`PreseasonEngine.CampCase`). Positive means he beat the spot.
        let caseScore: Double
        let verdict: PreseasonCampCase.Verdict
        /// One line of evidence: the play that carried the verdict, and how it
        /// sat against the bar. The recap's "who moved" list prints it verbatim.
        let reason: String
        let injured: Bool
        /// Scheme familiarity banked in this game (`VersatilityDevelopmentEngine`).
        let familiarityGain: Int

        /// The standout ranking: the same score, tilted toward the men whose
        /// roster spot is in question. See `PreseasonCampCase`.
        var standoutScore: Double {
            var value = caseScore
            if tier == .starter { value *= PreseasonCampCase.starterStandoutDiscount }
            if isRookie { value *= PreseasonCampCase.rookieStandoutBoost }
            return value
        }
    }

    let id: Int
    let gameIndex: Int
    /// "at Denver" / "vs Denver" — already carrying the venue word.
    let opponentLabel: String
    let userScore: Int
    let opponentScore: Int
    let policy: PreseasonPolicy
    /// Every user player with a stat line, best case first.
    let lines: [Line]
    /// Men who left the game hurt.
    let injuredNames: [String]
    /// Familiarity banked by the projected starters, which is what the policy
    /// was actually bought with.
    let starterFamiliarityGain: Int
    /// Injuries among the projected starters — the price of dressing them.
    let starterInjuryCount: Int

    // MARK: Derived

    var didWin: Bool { userScore > opponentScore }
    var didLose: Bool { userScore < opponentScore }

    var scoreText: String { "\(userScore)\u{2013}\(opponentScore)" }

    var resultLetter: String { didWin ? "W" : (didLose ? "L" : "T") }

    /// The cut cohort — everyone the ladder threatens.
    var cutCohort: [Line] { lines.filter { $0.tier.isCutCohort } }

    var helpedCount: Int { cutCohort.filter { $0.verdict == .helped }.count }
    var hurtCount: Int { cutCohort.filter { $0.verdict == .hurt }.count }

    /// Everyone whose case actually moved today, biggest move first — starters
    /// included, because a first-team quarterback who threw three picks is the
    /// most important thing that happened even though nobody is cutting him.
    ///
    /// This is what the screen prints as a NAMED list with a line of evidence
    /// each (#208 FIX C): "Helped 2 / Hurt 1" is a number, and a number is not
    /// the tape. The 65 is written from the sentences.
    var movers: [Line] {
        lines.filter { $0.verdict.moved }
            .sorted { abs($0.caseScore) > abs($1.caseScore) }
    }

    /// The starters inside `movers`, who are counted by neither `helpedCount`
    /// nor `hurtCount` — those two are the cut cohort's.
    ///
    /// Every screen that prints the two counts over the named list has to state
    /// this, or the arithmetic visibly fails: "4 helped, 1 hurt" sat above six
    /// names, and the tier pill that explained the sixth was behind the sheet.
    var starterMoverCount: Int { movers.filter { $0.tier == .starter }.count }

    /// The man the game belonged to, from the cutdown's point of view.
    var standout: Line? {
        lines.filter { $0.verdict == .helped }.max { $0.standoutScore < $1.standoutScore }
    }

    // MARK: - The one adapter
    //
    // Everything above is plain UI data. This initializer is the only code in
    // the preseason UI that knows what `PreseasonResult` looks like, so an
    // engine-side change to the payload lands here and nowhere else.

    /// - Parameters:
    ///   - result: the engine's payload for this game.
    ///   - policy: the coach decision this game was played under.
    ///   - opponentLabel: "at Denver" / "vs Denver", built by the caller from
    ///     the opponent `Team` and `result.matchup.isHome`.
    ///   - playersByID: the user's roster, for tier, name and OVR. A stat line
    ///     whose player is no longer on the roster is dropped — he was cut
    ///     between the game and this read, and a recap row for a man who is
    ///     gone is a ghost pointer.
    ///   - starterIDs: the lineup THIS game was played with, read off the
    ///     payload via `PreseasonResult.starterIDs(fallback:)`, so "starter"
    ///     means here exactly what it meant when the snaps were handed out —
    ///     not what it would mean on today's roster.
    init(
        result: PreseasonResult,
        policy: PreseasonPolicy,
        opponentLabel: String,
        playersByID: [UUID: Player],
        starterIDs: Set<UUID>
    ) {
        self.id = result.gameIndex
        self.gameIndex = result.gameIndex
        self.opponentLabel = opponentLabel
        // The payload already states the score from the user's point of view.
        self.userScore = result.userScore
        self.opponentScore = result.opponentScore
        self.policy = policy

        let injuredIDs = Set(result.injuries.map(\.playerID))
        // The engine persists the gains as an array of pairs (a JSON dictionary
        // cannot carry `UUID` keys); the lookup below wants them keyed.
        let gains = Dictionary(
            result.familiarityGains.map { ($0.playerID, $0.points) },
            uniquingKeysWith: { first, _ in first }
        )

        let built: [Line] = result.userLines.compactMap { stats in
            guard let player = playersByID[stats.playerID] else { return nil }
            // ONE engine call per man: verdict, case points and the sentence
            // behind them all come out of the same read.
            let read = PreseasonCampCase.read(stats)
            let isStarter = starterIDs.contains(stats.playerID)
            let isRookie = player.yearsPro == 0
            let tier: Tier
            if player.rosterStatus == .campBody {
                tier = .campBody
            } else if isStarter {
                tier = .starter
            } else if isRookie {
                tier = .rookie
            } else {
                tier = .bubble
            }
            return Line(
                id: stats.playerID,
                name: player.fullName,
                position: stats.position,
                overall: player.overall,
                age: player.age,
                contractYears: player.contractYearsRemaining,
                tier: tier,
                isRookie: isRookie,
                statLine: PreseasonCampCase.statLine(stats),
                caseScore: read.delta,
                verdict: PreseasonCampCase.Verdict(read.verdict),
                reason: read.reason,
                injured: injuredIDs.contains(stats.playerID),
                familiarityGain: gains[stats.playerID] ?? 0
            )
        }
        // Best case first: the table's job is to put the men who moved at the
        // top of the screen, not to reproduce a depth chart.
        .sorted { $0.standoutScore > $1.standoutScore }

        self.lines = built
        // The name is snapshotted on the payload, so a man cut between the game
        // and this read is still named rather than silently dropped.
        self.injuredNames = result.injuries.map(\.playerName)
        self.starterFamiliarityGain = gains.reduce(into: 0) { total, entry in
            if starterIDs.contains(entry.key) { total += entry.value }
        }
        self.starterInjuryCount = result.injuries.filter { starterIDs.contains($0.playerID) }.count
    }
}

// MARK: - Policy copy
//
// The engine owns the enum; the UI owns what it is called and how its trade-off
// is stated. Keeping the copy here is why `PreseasonEngine` carries no display
// strings — English-only, one home.

extension PreseasonPolicy {

    /// Fixed presentation order, hardest-resting first. Declared explicitly
    /// rather than taken from `CaseIterable` so the picker's order is a
    /// decision rather than an accident of declaration order.
    static let pickerOrder: [PreseasonPolicy] = [.startersRest, .starterSeries, .fullTilt]

    var displayTitle: String {
        switch self {
        case .startersRest: return "Rest the starters"
        case .starterSeries: return "A series for the ones"
        case .fullTilt:     return "Full tilt"
        }
    }

    /// What the club actually does. One sentence, no hedging.
    var displayDetail: String {
        switch self {
        case .startersRest:
            return "The first team stays in a cap. Everybody else plays the whole way."
        case .starterSeries:
            // #208 FIX C: a third of the FIRST TEAM opens, rotating across the
            // slate — the shape the engine actually plays now, and the copy the
            // decision is made on has to say so.
            return "A third of the ones open, rotating across the slate. The bubble plays the rest."
        case .fullTilt:
            return "Everybody plays it like it counts."
        }
    }

    /// The bet, in the two currencies the decision is actually made in.
    var familiarityNote: String {
        switch self {
        case .startersRest: return "No first-team install"
        case .starterSeries: return "Part install"
        case .fullTilt:     return "Full install"
        }
    }

    var riskNote: String {
        switch self {
        case .startersRest: return "No starter risk"
        case .starterSeries: return "Part starter risk"
        case .fullTilt:     return "Full starter risk"
        }
    }

    /// Pill tone for the risk column: resting is safe, full tilt is not.
    var riskTone: DSStatusPill.Tone {
        switch self {
        case .startersRest: return .ok
        case .starterSeries: return .warn
        case .fullTilt:     return .bad
        }
    }

    /// Pill tone for the install column, climbing as `riskTone` falls.
    ///
    /// The two pills are the two halves of one bet, so both axes have to move
    /// in colour or the scan lies: a flat blue install pill on all three rows
    /// beside a green → orange → red risk ramp said the benefit was constant
    /// and only the cost varied. `empty` for resting is the same statement the
    /// dashed chip makes everywhere else — the slot exists, nothing filled it.
    var familiarityTone: DSStatusPill.Tone {
        switch self {
        case .startersRest: return .empty
        case .starterSeries: return .info
        case .fullTilt:     return .ok
        }
    }

    var icon: String {
        switch self {
        case .startersRest: return "shield.lefthalf.filled"
        case .starterSeries: return "timer"
        case .fullTilt:     return "flame.fill"
        }
    }
}

// MARK: - The ending (§2.6)

/// The per-game result sheet: headline → what changed → what it cost → one
/// commit. Four chips, and the cost line is the price of the policy the user
/// chose — which is the whole point of having let him choose.
struct PreseasonRecapSheet: View {

    let recap: PreseasonRecap
    /// What the commit is called — "Set the plan for Game 2", "Final cuts".
    let continueTitle: String
    let onContinue: () -> Void

    var body: some View {
        DSResultSheet(
            tone: tone,
            eyebrow: "Preseason \u{00B7} Game \(recap.gameIndex)",
            headline: headline,
            message: message,
            chips: chips,
            cost: costLine,
            continueTitle: continueTitle,
            onContinue: onContinue
        )
    }

    // MARK: Tone and copy

    /// Preseason results do not stand for much, so the tone follows the ROSTER
    /// news rather than the scoreboard: a starter on the cart is a bad ending
    /// even in a win, and a bubble man playing his way onto the 53 is a good
    /// one even in a loss.
    private var tone: DSResultSheet.Tone {
        if recap.starterInjuryCount > 0 { return .bad }
        if recap.helpedCount > 0 { return .good }
        return .neutral
    }

    private var headline: String {
        let verb = recap.didWin ? "Won" : (recap.didLose ? "Lost" : "Tied")
        return "\(verb) \(recap.scoreText) \(recap.opponentLabel)"
    }

    private var message: String {
        var sentences: [String] = []

        if let standout = recap.standout {
            sentences.append(
                "**\(standout.name)** (\(standout.position.rawValue), \(standout.tier.pillLabel.lowercased())) "
                + "was the story: \(standout.statLine.lowercased())."
            )
        }

        let helped = recap.helpedCount
        let hurt = recap.hurtCount
        if helped == 0 && hurt == 0 {
            // Say WHY nobody moved. Under `.fullTilt` the answer is the policy
            // itself — the first team took the tape, which is what the user
            // bought — and a flat "nobody did enough" would read as the screen
            // failing rather than as the bet paying out the way it does.
            sentences.append(
                recap.policy == .fullTilt
                    ? "The ones took the afternoon, so the bubble left almost no tape to cut from."
                    : "Nobody on the bubble did enough either way to change the cut sheet."
            )
        } else {
            var line = "**\(helped)** of the men fighting for a spot helped "
            line += helped == 1 ? "his case" : "their case"
            if hurt > 0 {
                line += " and **\(hurt)** hurt \(hurt == 1 ? "his" : "theirs")"
            }
            // Neither count includes a starter, and the who-moved list behind
            // this sheet does. Without the clause the sentence is short by
            // however many of the ones had an afternoon.
            if recap.starterMoverCount > 0 {
                line += ", plus **\(recap.starterMoverCount)** starter"
                    + (recap.starterMoverCount == 1 ? " who moved" : "s who moved")
            }
            sentences.append(line + ".")
        }

        if !recap.injuredNames.isEmpty {
            let names = recap.injuredNames.prefix(3).joined(separator: ", ")
            sentences.append("Left hurt: \(names).")
        }

        return sentences.joined(separator: " ")
    }

    /// Four, and no fifth.
    ///
    /// The standout deliberately does NOT get a chip: `DSResultSheet` lays its
    /// chips as one `Grid` row, and a fifth column at the 720 pt content
    /// measure puts a surname in ~120 pt where `minimumScaleFactor(0.7)` stops
    /// shrinking and `clipped()` takes over. He is the first sentence of the
    /// message instead, which is where a name belongs anyway.
    private var chips: [DSResultSheet.Chip] {
        [
            .init(
                id: "score",
                label: "Score",
                value: recap.scoreText,
                context: recap.resultLetter,
                contextColor: recap.didWin ? .success : (recap.didLose ? .dangerText : .textTertiaryReadable)
            ),
            .init(
                id: "helped",
                label: "Helped",
                value: "\(recap.helpedCount)",
                // NOT "on the bubble". `cutCohort` is built from THIS game's
                // box score, so the denominator is who dressed and it moves
                // from game to game — 54 then 53, with no cut and no injury
                // between them, which read as a bug because the old wording
                // promised a roster fact.
                context: "of \(recap.cutCohort.count) who dressed",
                valueColor: recap.helpedCount > 0 ? .success : .textPrimary
            ),
            .init(
                id: "hurt",
                label: "Slipped",
                value: "\(recap.hurtCount)",
                context: recap.hurtCount > 0 ? "played themselves down" : "nobody slipped",
                valueColor: recap.hurtCount > 0 ? .dangerText : .textPrimary
            ),
            .init(
                id: "injuries",
                label: "Injuries",
                value: "\(recap.injuredNames.count)",
                context: recap.starterInjuryCount > 0
                    ? "\(recap.starterInjuryCount) starter\(recap.starterInjuryCount == 1 ? "" : "s")"
                    : "none among the ones",
                valueColor: recap.injuredNames.isEmpty ? .textPrimary : .dangerText,
                contextColor: recap.starterInjuryCount > 0 ? .dangerText : .textTertiaryReadable
            )
        ]
    }

    /// What the policy cost, in the two currencies §4.2 prices it in.
    private var costLine: String {
        switch recap.policy {
        case .startersRest:
            return "You banked **no first-team install** and took **no first-team risk**. "
                + "Week 1 opens on the playbook camp left you."
        case .starterSeries:
            var line = "The ones who opened banked **+\(recap.starterFamiliarityGain)** scheme familiarity"
            line += recap.starterInjuryCount > 0
                ? ", and **\(recap.starterInjuryCount)** of them paid for it."
                : ", and nobody paid for it."
            return line
        case .fullTilt:
            var line = "A full game for the ones: **+\(recap.starterFamiliarityGain)** scheme familiarity"
            line += recap.starterInjuryCount > 0
                ? ", at the price of **\(recap.starterInjuryCount)** injured starter\(recap.starterInjuryCount == 1 ? "" : "s")."
                : ", and this time it cost nothing."
            return line
        }
    }
}

// MARK: - The evidence

/// The bubble stat table, rendered on `PreseasonView` behind the sheet.
///
/// One `DSListRow` per man, best case first, on the shared list standard: a
/// position badge, the name, the outing under it, and the two pills that answer
/// the only question the screen is for — where does he stand, and did today
/// move him.
struct PreseasonBubbleTable: View {

    /// Which cohort the table is showing. The default is the cut cohort,
    /// because the cut sheet is what the screen is for.
    enum Cohort: String, CaseIterable, Hashable {
        case bubble
        case everyone

        /// "Cut sheet", not "On the bubble": the lens filters everyone the
        /// ladder threatens, and most of those men carry a BUBBLE standing pill
        /// on their own row while the rest carry CAMP or ROOK. A tab that told
        /// the reader seven men were on the bubble and then told him five of
        /// them were not had two meanings for one word.
        var label: String {
            switch self {
            case .bubble:   return "Cut sheet"
            case .everyone: return "Whole roster"
            }
        }
    }

    let recap: PreseasonRecap
    @Binding var cohort: Cohort

    private var visibleLines: [PreseasonRecap.Line] {
        switch cohort {
        case .bubble:   return recap.cutCohort
        case .everyone: return recap.lines
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            DSLensTabs(
                selection: $cohort,
                lenses: Cohort.allCases,
                label: { $0.label },
                title: "Tape"
            )

            if visibleLines.isEmpty {
                DSEmptyState(
                    icon: "list.bullet.rectangle",
                    title: "No stat lines",
                    message: cohort == .bubble
                        ? "Nobody outside the starting lineup registered in the box score."
                        : "This game produced no box score."
                )
            } else {
                header
                VStack(spacing: 0) {
                    ForEach(visibleLines) { line in
                        row(line)
                        if line.id != visibleLines.last?.id {
                            Divider().overlay(Color.surfaceBorder)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.sm)
                .cardBackground()
            }
        }
    }

    private var header: some View {
        DSListHeaderRow(
            density: .scan,
            reservesBadge: true,
            portraitWidth: 0,
            identityLabel: "Player \u{00B7} outing"
        ) {
            DSColumnHeader("OVR", width: DSListColumn.ovr)
            DSColumnHeader("Age", width: DSListColumn.tight)
            DSColumnHeader("Yrs", width: DSListColumn.tight)
            DSColumnHeader("Fam", width: DSListColumn.tight)
            DSColumnHeader("Standing", width: DSListColumn.label)
            DSColumnHeader("Case", width: DSListColumn.label)
        }
        .padding(.horizontal, DSSpacing.sm)
    }

    private func row(_ line: PreseasonRecap.Line) -> some View {
        DSListRow(
            density: .scan,
            badge: DSRowBadge(
                text: line.position.rawValue,
                tint: positionTint(line.position),
                accessibilityLabel: "\(line.position.rawValue), \(line.position.side.rawValue)"
            ),
            portraitWidth: 0
        ) {
            EmptyView()
        } identity: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(line.name)
                        .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if line.injured {
                        // An injury is a fact about the outing, so it travels
                        // with the name rather than competing for a column.
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.dangerText)
                            .accessibilityLabel("Left the game hurt")
                    }
                }
                Text(line.statLine)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } columns: {
            Text("\(line.overall)")
                .font(DSType.display(DSType.Size.body, .heavy))
                .foregroundStyle(Color.forRating(line.overall))
                .dsColumn(DSListColumn.ovr)

            // Both stay in the neutral text colour on purpose: a 31-year-old on
            // the last year of a deal is not a WARNING, it is a fact the coach
            // weighs, and this screen already carries as much tone as it can.
            Text("\(line.age)")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.tight)

            Text(line.contractYears > 0 ? "\(line.contractYears)" : "\u{2013}")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.tight)

            Text(line.familiarityGain > 0 ? "+\(line.familiarityGain)" : "\u{2013}")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(line.familiarityGain > 0 ? Color.success : Color.textTertiaryReadable)
                .dsColumn(DSListColumn.tight)

            DSStatusPill(label: line.tier.pillLabel, tone: line.tier.tone, showsDot: false)
                .dsColumn(DSListColumn.label)

            DSStatusPill(
                label: line.verdict.pillLabel,
                tone: line.verdict.tone,
                showsDot: false,
                spokenLabel: line.verdict.spoken
            )
            .dsColumn(DSListColumn.label)
        }
    }

    private func positionTint(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}
