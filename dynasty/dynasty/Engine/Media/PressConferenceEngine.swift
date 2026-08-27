import Foundation

// MARK: - Press Conference Models

struct PressQuestion: Identifiable, Codable {
    let id: UUID
    let reporterName: String
    let outlet: String
    let question: String
    let responses: [PressResponse]

    init(
        id: UUID = UUID(),
        reporterName: String,
        outlet: String,
        question: String,
        responses: [PressResponse]
    ) {
        self.id = id
        self.reporterName = reporterName
        self.outlet = outlet
        self.question = question
        self.responses = responses
    }
}

struct PressResponse: Identifiable, Codable {
    let id: UUID
    let text: String
    let tone: ResponseTone
    let mediaReaction: String
    let effects: PressEffects

    init(
        id: UUID = UUID(),
        text: String,
        tone: ResponseTone,
        mediaReaction: String,
        effects: PressEffects
    ) {
        self.id = id
        self.text = text
        self.tone = tone
        self.mediaReaction = mediaReaction
        self.effects = effects
    }
}

struct PressEffects: Codable {
    let ownerSatisfaction: Int
    let playerMorale: Int
    let mediaPerception: Int
    let legacyPoints: Int
    let fanExcitement: Int

    init(
        ownerSatisfaction: Int = 0,
        playerMorale: Int = 0,
        mediaPerception: Int = 0,
        legacyPoints: Int = 0,
        fanExcitement: Int = 0
    ) {
        self.ownerSatisfaction = ownerSatisfaction
        self.playerMorale = playerMorale
        self.mediaPerception = mediaPerception
        self.legacyPoints = legacyPoints
        self.fanExcitement = fanExcitement
    }

    /// Combine two effects by summing each field.
    static func + (lhs: PressEffects, rhs: PressEffects) -> PressEffects {
        PressEffects(
            ownerSatisfaction: lhs.ownerSatisfaction + rhs.ownerSatisfaction,
            playerMorale: lhs.playerMorale + rhs.playerMorale,
            mediaPerception: lhs.mediaPerception + rhs.mediaPerception,
            legacyPoints: lhs.legacyPoints + rhs.legacyPoints,
            fanExcitement: lhs.fanExcitement + rhs.fanExcitement
        )
    }
}

enum ResponseTone: String, Codable {
    case confident
    case humble
    case aggressive
    case diplomatic
    case funny

    var label: String {
        switch self {
        case .confident:  return "Confident"
        case .humble:     return "Humble"
        case .aggressive: return "Aggressive"
        case .diplomatic: return "Diplomatic"
        case .funny:      return "Funny"
        }
    }

    var icon: String {
        switch self {
        case .confident:  return "flame.fill"
        case .humble:     return "hand.raised.fill"
        case .aggressive: return "bolt.fill"
        case .diplomatic: return "scale.3d"
        case .funny:      return "face.smiling.fill"
        }
    }
}

// MARK: - Press Conference Result

/// Captures the player's choices from a completed press conference.
struct PressConferenceResult: Codable {
    let selectedResponses: [SelectedResponse]
    let totalEffects: PressEffects
    let dominantTone: ResponseTone
    /// #161: measurable claims, with the kind and threshold attached. Written
    /// into `Career.pressPromiseLedger` by `PressConferenceEngine.commit`.
    let promises: [PressConferenceEngine.PressPromiseRecord]

    struct SelectedResponse: Codable, Identifiable {
        let id: UUID
        let questionSummary: String
        let responseText: String
        let tone: ResponseTone
        let mediaReaction: String
        /// #161: the CONTEXT-RESOLVED cost of this answer — what the reveal
        /// prints after the player has committed to it. The authored base
        /// effects on `PressResponse` are an input to this, never the answer.
        let effects: PressEffects

        init(
            id: UUID = UUID(),
            questionSummary: String,
            responseText: String,
            tone: ResponseTone,
            mediaReaction: String,
            effects: PressEffects = PressEffects()
        ) {
            self.id = id
            self.questionSummary = questionSummary
            self.responseText = responseText
            self.tone = tone
            self.mediaReaction = mediaReaction
            self.effects = effects
        }
    }
}

// MARK: - Press Conference Engine

enum PressConferenceEngine {

    // MARK: - Last-Game Facts

    /// Concrete facts from the player's most recent game (quick-simmed or
    /// live-coached), distilled by `WeekAdvancer` from
    /// `WeekAdvancer.lastPlayerGameResult`. When present, the weekly presser
    /// swaps in questions that reference what actually happened; when nil,
    /// question selection is exactly the pre-R18 behavior.
    struct GameFacts {
        /// True when the player's team won.
        let won: Bool
        /// Absolute final margin.
        let margin: Int
        /// Sacks the player's offensive line surrendered.
        let sacksAllowed: Int
        /// The player-team rusher who cleared 100 yards, if any.
        let hundredYardRusherName: String?
        let hundredYardRusherYards: Int
        /// The opponent's abbreviation when the game was a division matchup
        /// (R19) — nil for non-division games. Swaps the post-game question
        /// for its rivalry variant.
        let divisionOpponentAbbr: String?
        /// R29: the team's spot in this week's league power rankings (1-32),
        /// nil when the narrative engine hasn't run yet.
        let powerRank: Int?
        /// R29: week-over-week ranking movement (+ = climbed).
        let powerRankMovement: Int
        /// R29: a player from this team inside the MVP top-3, if any.
        let mvpCandidateName: String?
        /// R29: that player's position in the race (1 = leading).
        let mvpCandidateRank: Int?

        init(
            won: Bool,
            margin: Int,
            sacksAllowed: Int,
            hundredYardRusherName: String?,
            hundredYardRusherYards: Int,
            divisionOpponentAbbr: String? = nil,
            powerRank: Int? = nil,
            powerRankMovement: Int = 0,
            mvpCandidateName: String? = nil,
            mvpCandidateRank: Int? = nil
        ) {
            self.won = won
            self.margin = margin
            self.sacksAllowed = sacksAllowed
            self.hundredYardRusherName = hundredYardRusherName
            self.hundredYardRusherYards = hundredYardRusherYards
            self.divisionOpponentAbbr = divisionOpponentAbbr
            self.powerRank = powerRank
            self.powerRankMovement = powerRankMovement
            self.mvpCandidateName = mvpCandidateName
            self.mvpCandidateRank = mvpCandidateRank
        }
    }

    /// Sacks allowed at or above this line trigger the protection question.
    private static let sackConcernThreshold = 4
    /// A loss by this margin or less counts as a heartbreaker.
    private static let narrowLossMargin = 3

    // MARK: - Reporters

    /// Fictional national press corps. Names and outlets are invented — no real
    /// journalist or broadcaster may appear here.
    private static let reporters: [(name: String, outlet: String)] = [
        ("Marcus Deane", "National Sports Network"),
        ("Renee Calloway", "National Sports Network"),
        ("Ty Brennan", "Continental Sports"),
        ("Vivian Osei", "Continental Sports"),
        ("Hal Marchetti", "The Gridiron Weekly"),
        ("Priya Raman", "The Gridiron Weekly"),
        ("Desmond Iyer", "Sunday Sports Wire"),
        ("Nora Whitlock", "Pressbox Daily"),
    ]

    private static let localReporters: [(name: String, outlet: String)] = [
        ("Beat Reporter", "Local Press"),
        ("Staff Writer", "City Tribune"),
        ("Sports Desk", "Local News 9"),
    ]

    private static func randomReporter() -> (name: String, outlet: String) {
        reporters.randomElement() ?? ("Marcus Deane", "National Sports Network")
    }

    private static func randomLocalReporter() -> (name: String, outlet: String) {
        localReporters.randomElement() ?? ("Beat Reporter", "Local Press")
    }

    /// Give every question in one conference a different masthead.
    ///
    /// Each generator draws its own reporter with `randomElement()` and knows
    /// nothing about the others, so a five-question session could — and on
    /// screen did — put THE GRIDIRON WEEKLY on slats 2 and 4 of the progress
    /// rail, which is the strip the player navigates the conference by. Doing
    /// it as a pass over the finished list leaves all twenty-odd generators
    /// alone and only breaks the collision.
    private static func dealDistinctOutlets(_ questions: [PressQuestion]) -> [PressQuestion] {
        var used: Set<String> = []
        let national = reporters.shuffled()
        let local = localReporters.shuffled()

        return questions.map { question in
            guard !used.insert(question.outlet).inserted else { return question }

            // A local-press question stays local: the outlet carries the
            // question's register, not just its name.
            let fromLocal = localReporters.contains { $0.outlet == question.outlet }
            guard let replacement = (fromLocal ? local : national).first(where: { !used.contains($0.outlet) })
            else { return question }
            used.insert(replacement.outlet)

            return PressQuestion(
                id: question.id,
                reporterName: replacement.name,
                outlet: replacement.outlet,
                question: question.question,
                responses: question.responses.map { restamp($0, from: question.outlet, to: replacement.outlet) }
            )
        }
    }

    /// Reaction headlines are authored as `"OUTLET: “…”"`, so a rewritten byline
    /// has to be rewritten there too — otherwise the reveal quotes a paper that
    /// never asked the question.
    private static func restamp(_ response: PressResponse, from old: String, to new: String) -> PressResponse {
        guard response.mediaReaction.hasPrefix(old) else { return response }
        return PressResponse(
            id: response.id,
            text: response.text,
            tone: response.tone,
            mediaReaction: new + String(response.mediaReaction.dropFirst(old.count)),
            effects: response.effects
        )
    }

    // MARK: - Intro Press Conference

    /// Generate 5-6 questions for the introductory press conference.
    static func generateIntroConference(team: Team, owner: Owner, career: Career) -> [PressQuestion] {
        var questions: [PressQuestion] = []

        // Q1: Vision for the franchise
        questions.append(generateVisionQuestion(team: team, owner: owner))

        // Q2: Salary cap situation
        questions.append(generateCapQuestion(team: team, career: career))

        // Q3: Message to the fans
        questions.append(generateFanMessageQuestion(team: team))

        // Q4: Upcoming draft
        questions.append(generateDraftQuestion(team: team))

        // The team-state wildcard, dealt into a rotating middle slot: the four
        // topics above are authored in a fixed order, so without this the very
        // first thing every career hears is the same four questions in the same
        // sequence. Never index 0 — the vision question is the opener by
        // design, and the room is asked what he is here to do before anything
        // else.
        questions.insert(
            generateInheritedRosterQuestion(team: team, owner: owner),
            at: Int.random(in: 1...questions.count)
        )

        // Media pressure (large market only) — still the closer.
        if team.mediaMarket == .large {
            questions.append(generateMediaPressureQuestion(team: team))
        }

        return dealDistinctOutlets(questions)
    }

    // MARK: - Weekly Press Conference

    /// Generate 2-3 questions for a weekly in-season press conference.
    /// - Parameter facts: Optional facts from the player's last game
    ///   (`nil` = pre-R18 question selection, used by every legacy call site).
    static func generateWeeklyPressConference(
        career: Career,
        team: Team,
        lastGameResult: Bool?,
        week: Int,
        facts: GameFacts? = nil
    ) -> [PressQuestion] {
        var questions: [PressQuestion] = []

        // Post-game question
        if let won = lastGameResult {
            if won {
                if let facts, facts.won, let rivalAbbr = facts.divisionOpponentAbbr {
                    // Beating a division rival gets the rivalry variant (R19).
                    questions.append(generateDivisionWinQuestion(team: team, rivalAbbr: rivalAbbr))
                } else {
                    questions.append(generatePostWinQuestion(team: team, week: week, facts: facts))
                }
            } else if let facts, !facts.won, facts.margin > 0, facts.margin <= narrowLossMargin {
                // A one-score heartbreaker gets its own question.
                questions.append(generateNarrowLossQuestion(team: team, margin: facts.margin))
            } else if let facts, !facts.won, let rivalAbbr = facts.divisionOpponentAbbr {
                // Losing inside the division stings in the standings (R19).
                questions.append(generateDivisionLossQuestion(team: team, rivalAbbr: rivalAbbr))
            } else {
                questions.append(generatePostLossQuestion(team: team, week: week))
            }
        }

        // Fact-based follow-up: protection meltdown or a 100-yard workhorse
        // takes the situational slot when the game actually produced one.
        var factQuestionUsed = false
        if let facts, facts.sacksAllowed >= sackConcernThreshold {
            questions.append(generateSacksAllowedQuestion(team: team, sacks: facts.sacksAllowed))
            factQuestionUsed = true
        } else if let facts, let rusherName = facts.hundredYardRusherName {
            questions.append(generateWorkhorseQuestion(
                team: team,
                rusherName: rusherName,
                yards: facts.hundredYardRusherYards
            ))
            factQuestionUsed = true
        }
        if factQuestionUsed {
            // Occasional third question, same odds as the regular path.
            // R29: a power-ranking / MVP-race angle takes the loose slot
            // about half the time when the storyline supports one.
            if Bool.random() {
                if let narrativeQ = generateNarrativeQuestion(team: team, facts: facts),
                   Bool.random() {
                    questions.append(narrativeQ)
                } else {
                    questions.append(generateLooseWeeklyQuestion(team: team))
                }
            }
            return dealDistinctOutlets(questions)
        }

        // Situational question — pick the most relevant one
        let totalGames = team.wins + team.losses

        // Compute a simple streak estimate from recent record context.
        // Positive = winning streak, negative = losing streak.
        let streakEstimate: Int = {
            guard let won = lastGameResult else { return 0 }
            // Use win % as a proxy: teams winning > 75% likely on a streak
            let winPct = totalGames > 0 ? Double(team.wins) / Double(totalGames) : 0.5
            if won && winPct >= 0.7 { return max(3, team.wins - team.losses) }
            if !won && winPct <= 0.3 { return min(-3, team.wins - team.losses) }
            return won ? 1 : -1
        }()

        if week == 1 {
            // Season opener
            questions.append(generateSeasonOpenerQuestion(team: team))
        } else if week == 18 {
            // Season finale
            questions.append(generateSeasonFinaleQuestion(team: team))
        } else if week == 8 || week == 9 {
            // Trade deadline window
            questions.append(generateTradeDeadlineQuestion(team: team))
        } else if streakEstimate >= 3 {
            // Winning streak (3+)
            questions.append(generateWinningStreakQuestion(team: team))
        } else if streakEstimate <= -3 {
            // Losing streak (3+)
            questions.append(generateLosingStreakQuestion(team: team))
        } else if totalGames >= 10 && team.wins >= 7 {
            questions.append(generatePlayoffPushQuestion(team: team))
        } else if totalGames >= 8 && team.losses > team.wins {
            questions.append(generateStruggleQuestion(team: team))
        } else {
            questions.append(generateGenericWeeklyQuestion(team: team, week: week))
        }

        // Occasional third question — R29: the power-ranking / MVP-race
        // angle takes the slot about half the time when one applies.
        if Bool.random() {
            if let narrativeQ = generateNarrativeQuestion(team: team, facts: facts),
               Bool.random() {
                questions.append(narrativeQ)
            } else {
                questions.append(generateLooseWeeklyQuestion(team: team))
            }
        }

        return dealDistinctOutlets(questions)
    }

    // MARK: - Aggregate Results

    /// Build a `PressConferenceResult` from the questions, the indices the
    /// player chose, and the context the conference opened in.
    ///
    /// #161: the effects here are CONTEXT-RESOLVED (`PressEngine.swift`), not
    /// the authored literals on `PressResponse`, and the context walks forward
    /// question by question exactly the way the screen walked it — so the
    /// repetition ratchet that dimmed the fourth Diplomatic answer on screen is
    /// the same one that books the totals.
    static func buildResult(
        questions: [PressQuestion],
        selectedIndices: [Int],
        context: PressContext
    ) -> PressConferenceResult {
        var selected: [PressConferenceResult.SelectedResponse] = []
        var total = PressEffects()
        var toneCounts: [ResponseTone: Int] = [:]
        var promises: [PressPromiseRecord] = []
        var live = context

        for (qi, si) in selectedIndices.enumerated() where qi < questions.count {
            let question = questions[qi]
            guard si < question.responses.count else { continue }
            let response = question.responses[si]

            let effects = resolvedEffects(for: response, question: question, context: live)

            selected.append(PressConferenceResult.SelectedResponse(
                questionSummary: question.question,
                responseText: response.text,
                tone: response.tone,
                mediaReaction: response.mediaReaction,
                effects: effects
            ))

            total = total + effects
            toneCounts[response.tone, default: 0] += 1

            if let kind = promiseKind(for: response) {
                promises.append(PressPromiseRecord(
                    kind: kind,
                    statement: response.text,
                    season: context.season
                ))
            }

            live = live.appending(tone: response.tone)
        }

        let dominant = toneCounts.max(by: { $0.value < $1.value })?.key ?? .diplomatic

        return PressConferenceResult(
            selectedResponses: selected,
            totalEffects: total,
            dominantTone: dominant,
            promises: promises
        )
    }

    // MARK: - Private Question Generators

    /// The introductory presser's team-state wildcard.
    ///
    /// The other four intro topics — vision, cap, fans, draft — are the same
    /// four sentences whatever club the coach walked into. This one is seeded
    /// on the roster he actually inherited, and deliberately through
    /// `standing(forTeam:roster:)`, the SAME band `introContext` reads: the
    /// question the room asks, the fogged hints on the cards and the resolved
    /// effects then all agree about what kind of team this is, instead of the
    /// wildcard carrying a private opinion of its own.
    ///
    /// "The same band" only holds if it is the same roster, so the read is
    /// `Team.currentRoster()` — the `teamID` query the view already ran to
    /// hand `introContext` its array (`PressConferenceView.roster`). The
    /// `players` relationship is a creation-time hand-off that no transaction
    /// maintains (see ``Team/players``, `TRADE_OVERHAUL_PLAN` §7.5
    /// "teamID-reads everywhere"); it happens to agree at career creation,
    /// which is the only moment this presser runs today, but agreeing by
    /// accident is exactly what the locked decision retired.
    ///
    /// Effects follow the shape the four authored siblings already use — the
    /// confident card buys fans and legacy at the owner's expense, humble buys
    /// the owner and the room and bores the fans, aggressive buys the back page
    /// and costs everything else, diplomatic is small and positive everywhere —
    /// and the one state-dependent cell is the owner's: promising a fast turn
    /// on a rebuilding roster is a bill a patient owner never agreed to, which
    /// is the same rule `generateVisionQuestion` applies to a title claim.
    private static func generateInheritedRosterQuestion(team: Team, owner: Owner) -> PressQuestion {
        let r = randomReporter()
        let band = standing(forTeam: team, roster: team.currentRoster())
        let ownerWinNow = owner.prefersWinNow

        let question: String
        // (answer, the headline that answer produces), per tone.
        let confident: (String, String)
        let humble: (String, String)
        let aggressive: (String, String)
        let diplomatic: (String, String)

        switch band {
        case .rebuilding:
            question = "Nobody outside this building rates this roster. How long before the \(team.name) matter again?"
            confident = (
                "I don't do three-year rebuilds. We'll be in the hunt next season.",
                "\(r.outlet): \u{201C}No rebuild in \(team.city) \u{2014} new GM sets the clock at one year.\u{201D}"
            )
            humble = (
                "It starts with the men already in this building. I'm not writing anybody off in week one.",
                "\(r.outlet): \u{201C}New \(team.city) boss backs the players he inherited.\u{201D}"
            )
            aggressive = (
                "There is a lot less here than people keep telling me there is.",
                "\(r.outlet): \u{201C}Brutal first verdict on the \(team.name) roster from its own GM.\u{201D}"
            )
            diplomatic = (
                "We're further away than this city deserves and closer than the outside thinks. Both are true.",
                "\(r.outlet): \u{201C}\(team.city) sells a rebuild without using the word.\u{201D}"
            )
        case .middling:
            question = "This roster has been stuck in the middle for years. How do you get it out?"
            confident = (
                "Mediocrity is a choice, and we're done making it.",
                "\(r.outlet): \u{201C}\u{2018}Mediocrity is a choice\u{2019} \u{2014} new \(team.city) GM declares it over.\u{201D}"
            )
            humble = (
                "You leave the middle by being better at the boring parts than anyone else. That's the whole job.",
                "\(r.outlet): \u{201C}New GM preaches the unglamorous route out of the middle.\u{201D}"
            )
            aggressive = (
                "Stuck in the middle is a personnel problem. I intend to change the personnel.",
                "\(r.outlet): \u{201C}Roster purge hinted at as \(team.city) GM blames personnel.\u{201D}"
            )
            diplomatic = (
                "Good teams get out of the middle a piece at a time. We'll add the right ones.",
                "\(r.outlet): \u{201C}\(team.name) promise incremental climb out of the pack.\u{201D}"
            )
        case .contender:
            question = "You're inheriting a team that can win right now. Does that make the job harder?"
            confident = (
                "It makes it simpler. This team is ready, and my job is not to get in its way.",
                "\(r.outlet): \u{201C}New \(team.city) GM says the window is open and he won't touch it.\u{201D}"
            )
            humble = (
                "A roster this good got here without me. I intend to learn it before I change any of it.",
                "\(r.outlet): \u{201C}Hands-off start promised for a ready-made \(team.name) roster.\u{201D}"
            )
            aggressive = (
                "Ready to win now? Then somebody should explain to me why it hasn't happened yet.",
                "\(r.outlet): \u{201C}Shots at the old regime as new GM questions \(team.city)'s near misses.\u{201D}"
            )
            diplomatic = (
                "A good roster is a starting point, not a finish line. We'll keep adding.",
                "\(r.outlet): \u{201C}\(team.name) leadership preaches continuity with upgrades.\u{201D}"
            )
        }

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: question,
            responses: [
                // Confident: best Fans, strong Legacy. Cost: the owner, unless
                // he wanted it now anyway.
                PressResponse(
                    text: confident.0,
                    tone: .confident,
                    mediaReaction: confident.1,
                    effects: PressEffects(
                        ownerSatisfaction: band == .rebuilding && !ownerWinNow ? -6 : 3,
                        playerMorale: 3,
                        mediaPerception: 5,
                        legacyPoints: 8,
                        fanExcitement: 12
                    )
                ),
                // Humble: best Owner trust, best Morale. Cost: fans bored.
                PressResponse(
                    text: humble.0,
                    tone: .humble,
                    mediaReaction: humble.1,
                    effects: PressEffects(
                        ownerSatisfaction: 9,
                        playerMorale: 6,
                        mediaPerception: 3,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
                // Aggressive: best Media buzz, hurts everything else — and it
                // is the roster he is about to coach that he just criticised.
                PressResponse(
                    text: aggressive.0,
                    tone: .aggressive,
                    mediaReaction: aggressive.1,
                    effects: PressEffects(
                        ownerSatisfaction: -7,
                        playerMorale: -11,
                        mediaPerception: 18,
                        legacyPoints: 5,
                        fanExcitement: 2
                    )
                ),
                // Diplomatic: balanced positives, no negatives — the safe choice.
                PressResponse(
                    text: diplomatic.0,
                    tone: .diplomatic,
                    mediaReaction: diplomatic.1,
                    effects: PressEffects(
                        ownerSatisfaction: 4,
                        playerMorale: 4,
                        mediaPerception: 3,
                        legacyPoints: 3,
                        fanExcitement: 4
                    )
                ),
            ]
        )
    }

    private static func generateVisionQuestion(team: Team, owner: Owner) -> PressQuestion {
        let r = randomReporter()
        let ownerWinNow = owner.prefersWinNow

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "What's your vision for this franchise?",
            responses: [
                // Confident: Best Fans, big Legacy. Risk: Owner penalty if not win-now, slight Morale hit
                PressResponse(
                    text: "We're going to bring a championship to \(team.city). That's the only goal.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}Bold promise from the new front office leader!\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: ownerWinNow ? 4 : -6,
                        playerMorale: -2,
                        mediaPerception: 5,
                        legacyPoints: 10,
                        fanExcitement: 14
                    )
                ),
                // Humble: Best Owner trust, best Morale. Cost: Fans bored
                PressResponse(
                    text: "First, I need to understand what we have. Then we build, brick by brick.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}New leader takes measured approach in \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 10,
                        playerMorale: 6,
                        mediaPerception: 3,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
                // Aggressive: Best Media buzz. Cost: Morale tanks, owner unhappy
                PressResponse(
                    text: "This roster needs a complete overhaul. There are going to be a lot of changes.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}New GM already critical of \(team.name) roster!\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: ownerWinNow ? -10 : 2,
                        playerMorale: -12,
                        mediaPerception: 20,
                        legacyPoints: 5,
                        fanExcitement: 4
                    )
                ),
                // Diplomatic: Balanced positives across all axes, never negative — the safe choice
                PressResponse(
                    text: "There's talent here. We'll evaluate everything and add the right pieces.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Steady hand takes the reins in \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 4,
                        playerMorale: 4,
                        mediaPerception: 4,
                        legacyPoints: 3,
                        fanExcitement: 4
                    )
                ),
            ]
        )
    }

    private static func generateCapQuestion(team: Team, career: Career) -> PressQuestion {
        let r = randomReporter()
        let capTight = team.availableCap < 20_000

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "How do you plan to handle the salary cap situation?",
            responses: [
                // Confident: Best Fans excitement, strong Legacy. Risk: Owner penalty if cap tight
                PressResponse(
                    text: "We'll be aggressive. You have to spend money to win in this league.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) expected to be big spenders this offseason.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: capTight ? -8 : 2,
                        playerMorale: 4,
                        mediaPerception: 4,
                        legacyPoints: 8,
                        fanExcitement: 14
                    )
                ),
                // Diplomatic: Balanced positives, no negatives — the safe choice
                PressResponse(
                    text: "The cap is a tool. We need to be smart, not reckless.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}New front office preaches fiscal discipline.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 3,
                        mediaPerception: 3,
                        legacyPoints: 3,
                        fanExcitement: 3
                    )
                ),
                // Aggressive: Best Media buzz, hurts everything else
                PressResponse(
                    text: "Some of these contracts are... let's just say I have a lot of work to do.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Shots fired? New GM hints at roster purge.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -6,
                        playerMorale: -10,
                        mediaPerception: 20,
                        legacyPoints: 5,
                        fanExcitement: 2
                    )
                ),
                // Humble: Best Owner satisfaction, best Morale. Cost: Fans bored
                PressResponse(
                    text: "I inherited a situation. I'll learn the books, then make my moves.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Patience is the word in \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 10,
                        playerMorale: 6,
                        mediaPerception: 4,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
            ]
        )
    }

    private static func generateFanMessageQuestion(team: Team) -> PressQuestion {
        let r = randomLocalReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "What's your message to the fans of the \(team.name)?",
            responses: [
                // Confident (parade route): TRUE high risk/high reward — best Legacy, big Fans
                // +20 legacy if delivered (tracked via promise), but owner/morale risk
                PressResponse(
                    text: "Start planning the parade route.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}PARADE ROUTE?! New GM goes all-in on championship promise.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -7,
                        playerMorale: -4,
                        mediaPerception: 8,
                        legacyPoints: 20,
                        fanExcitement: 14
                    )
                ),
                // Humble: Best Owner trust, best Morale. Cost: Fans disappointed
                PressResponse(
                    text: "Trust the process. We're going to earn your support every single day.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}New leadership asks fans for patience and trust.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 9,
                        playerMorale: 6,
                        mediaPerception: 4,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
                // Funny: Best Fans, big locker room boost. Cost: Media credibility hit
                PressResponse(
                    text: "I promise -- the hot dogs at the stadium are going to be better this year.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}LOL -- new GM wins over the press room with humor.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 1,
                        playerMorale: 7,
                        mediaPerception: -4,
                        legacyPoints: 1,
                        fanExcitement: 16
                    )
                ),
                // Diplomatic: Balanced positives, no negatives — the safe choice
                PressResponse(
                    text: "This is your team. I'm just here to make sure we give you something to cheer about.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Humble words from the new man in charge.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 4,
                        playerMorale: 4,
                        mediaPerception: 4,
                        legacyPoints: 3,
                        fanExcitement: 5
                    )
                ),
            ]
        )
    }

    private static func generateDraftQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "What about the upcoming draft? How are you approaching it?",
            responses: [
                // Confident: Best Fans/Legacy. Cost: Owner penalty (perceived as inflexible)
                PressResponse(
                    text: "We're going to take the best player available. Period. No reaching.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}BPA philosophy for the new \(team.name) regime.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: 2,
                        mediaPerception: 4,
                        legacyPoints: 10,
                        fanExcitement: 10
                    )
                ),
                // Humble: Best Owner trust, best Morale. Cost: Fans bored
                PressResponse(
                    text: "I need to study the tape. I don't want to commit to a strategy before I've done my homework.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}New GM wants to see film before making draft plans.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 8,
                        playerMorale: 5,
                        mediaPerception: 4,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
                // Aggressive: Best Media buzz. Cost: hurts everything else
                PressResponse(
                    text: "If we can trade back and stockpile picks, that's what we're doing. Quantity has a quality of its own.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Trade-back strategy on the table for \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -7,
                        playerMorale: -8,
                        mediaPerception: 18,
                        legacyPoints: 5,
                        fanExcitement: -3
                    )
                ),
                // Diplomatic: Balanced positives, no negatives — the safe choice
                PressResponse(
                    text: "The draft is how you build dynasties. We're going to nail this.",
                    tone: .diplomatic,
                    // Its three siblings above quote the ANSWER back ("BPA
                    // philosophy", "wants to see film", "trade-back strategy");
                    // this one used to restate the QUESTION's topic, so the one
                    // safe card was also the only card the room heard nothing in.
                    mediaReaction: "\(r.outlet): \u{201C}Dynasty talk \u{2014} new \(team.city) GM stakes his tenure on nailing the draft.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 4,
                        playerMorale: 4,
                        mediaPerception: 3,
                        legacyPoints: 3,
                        fanExcitement: 4
                    )
                ),
            ]
        )
    }

    private static func generateMediaPressureQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "How do you handle the media pressure in \(team.city)?",
            responses: [
                // Confident: Big Legacy, strong Fans. Cost: Owner/Morale risk
                PressResponse(
                    text: "I thrive in it. The bigger the stage, the better I perform.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}Fearless attitude from the new front office boss.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -4,
                        playerMorale: -3,
                        mediaPerception: 5,
                        legacyPoints: 12,
                        fanExcitement: 10
                    )
                ),
                // Aggressive: Best Legacy. Cost: Media tanked, owner unhappy
                PressResponse(
                    text: "I don't read the papers. I just do my job.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}New GM seems uninterested in cozy media relationships.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -6,
                        playerMorale: 6,
                        mediaPerception: -10,
                        legacyPoints: 15,
                        fanExcitement: 8
                    )
                ),
                // Diplomatic: Best Owner trust + best Media, balanced positives, no negatives
                PressResponse(
                    text: "I respect the media. You have a job to do, and so do I. Let's work together.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Refreshing transparency from the new regime.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 6,
                        playerMorale: 3,
                        mediaPerception: 6,
                        legacyPoints: 3,
                        fanExcitement: 3
                    )
                ),
                // Funny: Best Fans, best Morale. Cost: Media credibility hit
                PressResponse(
                    text: "Pressure? I've been under pressure my whole career. This is Tuesday for me.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}Ha! New GM keeps it cool under the bright lights.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 2,
                        playerMorale: 8,
                        mediaPerception: -3,
                        legacyPoints: 2,
                        fanExcitement: 16
                    )
                ),
            ]
        )
    }

    // MARK: - Weekly Question Generators

    /// One authored line out of several. Variadic so a pool cannot be empty and
    /// the call sites never force-unwrap `randomElement()`.
    private static func oneOf(_ first: String, _ rest: String...) -> String {
        ([first] + rest).randomElement() ?? first
    }

    /// The opener after a win — the one question the coach faces most weeks of
    /// his career, and therefore the worst slot in this file to author once.
    /// A single line and a single triple of answers made Week 2 and Week 18
    /// byte-identical apart from the number, while `PressEngine`'s repetition
    /// ratchet was busy penalising the player for repeating a TONE.
    ///
    /// Nothing here moves an effect: the three answers keep their tones, their
    /// reactions and their numbers, and only the wording is drawn from a pool.
    /// The margin picks the register when `WeekAdvancer` handed the conference
    /// a box score; without one, the phrasing is the generic pool.
    private static func generatePostWinQuestion(team: Team, week: Int, facts: GameFacts? = nil) -> PressQuestion {
        let r = randomReporter()

        // The margin is only the margin when the box score agrees this was the
        // win — `facts` is nil on the legacy call path.
        let margin = facts.map { $0.won ? $0.margin : 0 } ?? 0
        let question: String = {
            let pool: [String]
            switch margin {
            case 17...:
                pool = [
                    "You were never threatened out there. What does a \(margin)-point win say about this team?",
                    "That one was decided by the fourth quarter. Where is this team ahead of where you expected?",
                    "\(margin) points in Week \(week) — what is clicking right now?",
                ]
            case 1...3:
                pool = [
                    "You survived that one by \(margin). Comfortable with how close it got?",
                    "One score, right to the whistle. What won it for you?",
                    "Week \(week) came down to the last drive. What does that tell you about your team?",
                ]
            default:
                pool = [
                    "Great win in Week \(week). What worked out there?",
                    "You got it done in Week \(week). What are you taking out of it?",
                    "Week \(week) goes in the win column. What pleased you most?",
                    "A win in Week \(week) — where did this one turn?",
                ]
            }
            return pool.randomElement() ?? "Great win in Week \(week). What worked out there?"
        }()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: question,
            responses: [
                PressResponse(
                    text: oneOf(
                        "The guys executed the game plan perfectly. That's what happens when you prepare.",
                        "We executed. That is what preparation looks like on a Sunday afternoon.",
                        "That's the version of this team we practise every week. Nobody in our building is surprised."
                    ),
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) clicking on all cylinders.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: oneOf(
                        "Credit goes to the players and coaches. They put in the work all week.",
                        "That's the players and the assistants. They did the work; I watched it pay off.",
                        "I had very little to do with that. Those men earned it on Wednesday and Thursday."
                    ),
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Humble leader deflects credit to the locker room.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: oneOf(
                        "We won but we left a lot on the table. We need to be better.",
                        "We left points out there. A win is a win, but that tape is going to be uncomfortable.",
                        "I'm not going to stand up here and call that clean. We have to be sharper than that."
                    ),
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Even after a win, \(team.name) boss demands more.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: -5,
                        mediaPerception: 10,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    private static func generatePostLossQuestion(team: Team, week: Int) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "Tough loss in Week \(week). What went wrong?",
            responses: [
                PressResponse(
                    text: "That's on me. I'll take responsibility. We'll fix it.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) leader falls on the sword after loss.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 10,
                        legacyPoints: 3,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "We got outplayed. Simple as that. Time to look in the mirror.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Frustration mounting in the \(team.name) building.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: -10,
                        mediaPerception: 10,
                        legacyPoints: 1,
                        fanExcitement: -5
                    )
                ),
                PressResponse(
                    text: "One game doesn't define us. We'll respond next week.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) GM confident despite setback.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "I'm not going to throw anyone under the bus. We win and lose as a team.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}United front in \(team.city) despite the loss.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    // MARK: - Fact-Based Weekly Questions (R18)

    /// Loss by 3 or fewer — the reporters want to know about the fine margins.
    private static func generateNarrowLossQuestion(team: Team, margin: Int) -> PressQuestion {
        let r = randomReporter()
        let pointWord = margin == 1 ? "point" : "points"

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "A \(margin)-\(pointWord) loss that came down to the final possession. What separates close from winning?",
            responses: [
                PressResponse(
                    text: "One play here or there. Finding those \(margin) \(pointWord) is my job, and I'll find them.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) leader owns the fine margins after narrow defeat.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 10,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "We're right there. Flip one snap and we're having a very different conversation.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) see themselves a play away.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "Close doesn't count in this league. Nobody in that locker room gets a pass for 'almost'.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}No moral victories in \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: -10,
                        mediaPerception: 15,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    /// The line surrendered a pile of sacks — protection is the story.
    private static func generateSacksAllowedQuestion(team: Team, sacks: Int) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "Your line gave up \(sacks) sacks — is protection a concern?",
            responses: [
                PressResponse(
                    text: "That's on all of us — scheme, calls, execution. We'll get it fixed in the protection meetings this week.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) promise answers up front after \(sacks)-sack afternoon.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 8,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "\(sacks) sacks is unacceptable. Jobs are on the line up front, and everybody knows it.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) boss puts the offensive line on notice.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: -10,
                        mediaPerception: 15,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "Credit their rush — they brought looks we hadn't seen. Our quarterback is fine, and we have the answers.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) unshaken despite the pressure numbers.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 3
                    )
                ),
            ]
        )
    }

    /// A back cleared 100 yards — feed him more?
    private static func generateWorkhorseQuestion(
        team: Team,
        rusherName: String,
        yards: Int
    ) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "\(rusherName) ran for \(yards) yards — is he your workhorse now?",
            responses: [
                PressResponse(
                    text: "He's a bell cow. When he runs like that, we're a very tough team to beat.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) commit to the ground game behind \(rusherName).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 10
                    )
                ),
                PressResponse(
                    text: "We ride the hot hand. \(rusherName) earned every one of those yards, but it stays a committee.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) keeping the backfield plan flexible.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 3,
                        legacyPoints: 1,
                        fanExcitement: 3
                    )
                ),
                PressResponse(
                    text: "I might hand it to him 40 times next week. Somebody should probably warn his agent.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}Ha — \(team.city) falling in love with its running back.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 8,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 12
                    )
                ),
            ]
        )
    }

    // MARK: - Division Rivalry Questions (R19)

    /// Won a division game — the standings and the rivalry are the story.
    private static func generateDivisionWinQuestion(team: Team, rivalAbbr: String) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "A win over \(rivalAbbr) inside the division — how much bigger do these ones feel?",
            responses: [
                PressResponse(
                    text: "Division games are worth double — them losing, us winning. That's how you take the \(team.conference.rawValue) \(team.division.rawValue).",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) planting a flag in the division race.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 10
                    )
                ),
                PressResponse(
                    text: "They know us, we know them — those are the hardest wins in football. Credit the locker room.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Respect for the rivalry from the \(team.name) boss.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "One division win doesn't hang a banner. Ask me again when we've swept the round-robin.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.city) wants more than a rivalry scalp.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: -5,
                        mediaPerception: 10,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
            ]
        )
    }

    /// Lost a division game — a defeat that counts twice in the standings.
    private static func generateDivisionLossQuestion(team: Team, rivalAbbr: String) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "Losing to \(rivalAbbr) hurts twice in the division standings. How costly was this one?",
            responses: [
                PressResponse(
                    text: "Division losses are on the head coach. I'll wear this one, and we'll be ready for the rematch.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) leader owns the division stumble.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 10,
                        legacyPoints: 3,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "The race is long. Nobody wins the \(team.conference.rawValue) \(team.division.rawValue) in one afternoon — and nobody loses it in one either.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) GM unshaken by the rivalry defeat.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "Circle the rematch. That result is going up on the wall of our building, and they know it.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Rivalry heat rising between \(team.city) and \(rivalAbbr).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: -5,
                        mediaPerception: 15,
                        legacyPoints: 1,
                        fanExcitement: 10
                    )
                ),
            ]
        )
    }

    // MARK: - League Narrative Questions (R29)

    /// A power-ranking or MVP-race angle for the loose weekly slot. Returns
    /// nil when neither storyline applies to this team right now.
    private static func generateNarrativeQuestion(
        team: Team,
        facts: GameFacts?
    ) -> PressQuestion? {
        guard let facts else { return nil }

        var options: [PressQuestion] = []
        if let rank = facts.powerRank,
           rank <= 5 || abs(facts.powerRankMovement) >= 5 {
            options.append(generatePowerRankQuestion(
                team: team, rank: rank, movement: facts.powerRankMovement
            ))
        }
        if let name = facts.mvpCandidateName, let raceRank = facts.mvpCandidateRank {
            options.append(generateMVPRaceQuestion(
                team: team, playerName: name, raceRank: raceRank
            ))
        }
        return options.randomElement()
    }

    /// The team sits high in (or moved sharply through) the power rankings.
    private static func generatePowerRankQuestion(
        team: Team,
        rank: Int,
        movement: Int
    ) -> PressQuestion {
        let r = randomReporter()
        let question: String
        if movement >= 5 {
            question = "You jumped \(movement) spots to No. \(rank) in this week's power rankings. Is this team finally getting the respect it deserves?"
        } else if movement <= -5 {
            question = "You dropped \(abs(movement)) spots to No. \(rank) in the power rankings this week. Do those lists mean anything inside the building?"
        } else if rank == 1 {
            question = "The power rankings have you as the No. 1 team in the league. How do you handle being the hunted?"
        } else {
            question = "The pundits have you at No. \(rank) in the league this week. Does that match how you see this team?"
        }

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: question,
            responses: [
                PressResponse(
                    text: "Rankings in \(rank <= 5 ? "November" : "midseason") don't hang banners. The only list that matters is the one in January.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) boss dismisses the rankings talk.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 10,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "It's a nice nod to the work the players put in, but we know how fast those lists flip.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Level heads in \(team.city) despite the rankings buzz.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "Honestly? I had us higher.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}Ha — \(team.name) front office wants an even better seed on the board.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 8,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 12
                    )
                ),
            ]
        )
    }

    /// One of the team's stars is in the MVP top-3.
    private static func generateMVPRaceQuestion(
        team: Team,
        playerName: String,
        raceRank: Int
    ) -> PressQuestion {
        let r = randomReporter()
        let question = raceRank == 1
            ? "\(playerName) leads the MVP race right now. What makes his season special?"
            : "\(playerName) is squarely in the MVP conversation. How is he handling the spotlight?"

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: question,
            responses: [
                PressResponse(
                    text: "He's the best player in football, and it's not particularly close. Watch the tape.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) go all-in on \(playerName)'s MVP campaign.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 12,
                        mediaPerception: 8,
                        legacyPoints: 2,
                        fanExcitement: 12
                    )
                ),
                PressResponse(
                    text: "Individual awards follow team success. He'd tell you the same thing — wins first.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Team-first message around \(playerName)'s award chatter.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 3
                    )
                ),
                PressResponse(
                    text: "We don't talk about it in the building. The minute you chase trophies, you stop chasing wins.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.city) keeping the MVP noise outside the walls.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    private static func generatePlayoffPushQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "The \(team.name) are in the playoff hunt. Are you feeling the pressure?",
            responses: [
                PressResponse(
                    text: "Pressure is a privilege. We want to be in these moments.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) embracing the playoff spotlight.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 10,
                        legacyPoints: 3,
                        fanExcitement: 15
                    )
                ),
                PressResponse(
                    text: "We're taking it one week at a time. That hasn't changed.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Steady as she goes for \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 0,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "Playoffs? I'm already thinking about the Championship.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}CHAMPIONSHIP?! \(team.name) GM looking past the competition?\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 20,
                        legacyPoints: 5,
                        fanExcitement: 20
                    )
                ),
            ]
        )
    }

    private static func generateStruggleQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "The season hasn't gone as planned. What changes are you considering?",
            responses: [
                PressResponse(
                    text: "We're evaluating everything. Nothing is off the table.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Shakeup looming in \(team.city)?\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: -10,
                        mediaPerception: 15,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "I still believe in this group. We have the talent to turn it around.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) boss standing behind the roster.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "We knew this might be a tough year. We're building for the long term.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Patience remains the word in \(team.city).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: 0,
                        mediaPerception: 0,
                        legacyPoints: 1,
                        fanExcitement: -10
                    )
                ),
            ]
        )
    }

    private static func generateGenericWeeklyQuestion(team: Team, week: Int) -> PressQuestion {
        let r = randomLocalReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "How is the team preparing for Week \(week + 1)?",
            responses: [
                PressResponse(
                    text: "Same as every week. We prepare, we compete, we execute.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}Business as usual for the \(team.name).\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 5,
                        mediaPerception: 0,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "We've identified some things we need to clean up. The focus is on fundamentals.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) focused on details heading into next week.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "I can't give away our game plan! Nice try though.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}Ha -- good luck getting secrets out of this front office.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 5,
                        mediaPerception: 10,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
            ]
        )
    }

    private static func generateLooseWeeklyQuestion(team: Team) -> PressQuestion {
        let r = randomLocalReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "How's the mood in the locker room?",
            responses: [
                PressResponse(
                    text: "Focused. This group is locked in.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) locker room united, per sources.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "We're having fun out there. When you're having fun, good things happen.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}Good vibes in \(team.city) -- players enjoying the season.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 10
                    )
                ),
                PressResponse(
                    text: "I'll keep that between us and the locker room.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Tight-lipped approach from \(team.name) front office.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 5,
                        mediaPerception: -5,
                        legacyPoints: 0,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    // MARK: - Situational Question Generators

    private static func generateWinningStreakQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "The \(team.name) are on a hot streak. What's driving this run?",
            responses: [
                PressResponse(
                    text: "We built this roster to win. It's no surprise -- this is what we expected.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) boss expected nothing less than dominance.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 10,
                        legacyPoints: 3,
                        fanExcitement: 10
                    )
                ),
                PressResponse(
                    text: "The players deserve all the credit. They've been grinding every single day.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}Selfless leadership fueling the \(team.name) surge.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "We're not satisfied yet. Winning streaks don't mean anything in January.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}Even on a roll, \(team.name) front office wants more.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: -5,
                        mediaPerception: 10,
                        legacyPoints: 2,
                        fanExcitement: 0
                    )
                ),
            ]
        )
    }

    private static func generateLosingStreakQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "The losses keep piling up. Is there a plan to turn things around?",
            responses: [
                PressResponse(
                    text: "Absolutely. We know what the issues are and we're addressing them.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) insists the turnaround is coming.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "We need to look in the mirror. Everyone. Starting with me.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) leader takes accountability amid losing streak.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 10,
                        legacyPoints: 3,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "Changes are coming. I can promise you that.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}SHAKEUP? \(team.name) boss hints at major changes.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: -15,
                        mediaPerception: 20,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "Rome wasn't built in a day. We're building something here.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Patience is the message in \(team.city) despite struggles.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: 5,
                        mediaPerception: 0,
                        legacyPoints: 1,
                        fanExcitement: -10
                    )
                ),
            ]
        )
    }

    private static func generateTradeDeadlineQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "The trade deadline is approaching. Are the \(team.name) buyers or sellers?",
            responses: [
                PressResponse(
                    text: "We're all-in. If there's a move that makes us better, we're making it.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) going for it at the trade deadline!\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 15,
                        legacyPoints: 3,
                        fanExcitement: 15
                    )
                ),
                PressResponse(
                    text: "We're evaluating. We won't mortgage the future for a rental.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) taking measured approach to deadline.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 0,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "We're listening to offers on everyone. Nobody is untouchable.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \u{201C}FIRE SALE? \(team.name) open for business at the deadline.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: -15,
                        mediaPerception: 20,
                        legacyPoints: 2,
                        fanExcitement: -5
                    )
                ),
                PressResponse(
                    text: "I'm not going to tip my hand. You'll see what we do on deadline day.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) keeping trade plans close to the vest.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 0,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
            ]
        )
    }

    private static func generateSeasonOpenerQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "Opening day is here. What are the expectations for the \(team.name) this season?",
            responses: [
                PressResponse(
                    text: "We're here to compete for a championship. Anything less is a failure.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \u{201C}Championship or bust for the \(team.name)!\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 10,
                        legacyPoints: 5,
                        fanExcitement: 15
                    )
                ),
                PressResponse(
                    text: "We want to improve every week and see where the season takes us.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \u{201C}\(team.name) taking it one step at a time.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "The offseason work is done. Now it's time to let the football do the talking.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \u{201C}Confidence in \(team.city) as the new season kicks off.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
            ]
        )
    }

    private static func generateSeasonFinaleQuestion(team: Team) -> PressQuestion {
        let r = randomReporter()
        let madePlayoffs = (team.wins + team.losses) > 0 && team.wins >= 9

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: madePlayoffs
                ? "Final week of the regular season. How does this team feel heading into the playoffs?"
                : "The regular season is wrapping up. How do you evaluate this year?",
            responses: [
                PressResponse(
                    text: madePlayoffs
                        ? "We're battle-tested. Bring on the playoffs."
                        : "There were growing pains, but the foundation is stronger now.",
                    tone: .confident,
                    mediaReaction: madePlayoffs
                        ? "\(r.outlet): \u{201C}\(team.name) ready for the postseason stage.\u{201D}"
                        : "\(r.outlet): \u{201C}\(team.name) boss sees progress despite the record.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: madePlayoffs ? 5 : 0,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: madePlayoffs ? 3 : 1,
                        fanExcitement: madePlayoffs ? 10 : 0
                    )
                ),
                PressResponse(
                    text: madePlayoffs
                        ? "One game at a time. That mentality got us here."
                        : "I owe the fans better. We'll work harder this offseason.",
                    tone: .humble,
                    mediaReaction: madePlayoffs
                        ? "\(r.outlet): \u{201C}Focused mindset from \(team.city) heading into January.\u{201D}"
                        : "\(r.outlet): \u{201C}\(team.name) leader vows to do better next year.\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: madePlayoffs ? 5 : 5,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: madePlayoffs ? 5 : -5
                    )
                ),
                PressResponse(
                    text: madePlayoffs
                        ? "The regular season was just the appetizer. The real show starts now."
                        : "I've already started making calls. Big changes are coming.",
                    tone: .aggressive,
                    mediaReaction: madePlayoffs
                        ? "\(r.outlet): \u{201C}\(team.name) treating playoffs as their true stage.\u{201D}"
                        : "\(r.outlet): \u{201C}Offseason overhaul incoming in \(team.city)?\u{201D}",
                    effects: PressEffects(
                        ownerSatisfaction: madePlayoffs ? 5 : 0,
                        playerMorale: madePlayoffs ? 5 : -10,
                        mediaPerception: 15,
                        legacyPoints: madePlayoffs ? 3 : 2,
                        fanExcitement: madePlayoffs ? 15 : 5
                    )
                ),
            ]
        )
    }
}
