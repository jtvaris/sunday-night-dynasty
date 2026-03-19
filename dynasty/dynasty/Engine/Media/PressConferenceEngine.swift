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
    let promises: [LegacyTracker.PressPromise]

    struct SelectedResponse: Codable, Identifiable {
        let id: UUID
        let questionSummary: String
        let responseText: String
        let tone: ResponseTone
        let mediaReaction: String

        init(
            id: UUID = UUID(),
            questionSummary: String,
            responseText: String,
            tone: ResponseTone,
            mediaReaction: String
        ) {
            self.id = id
            self.questionSummary = questionSummary
            self.responseText = responseText
            self.tone = tone
            self.mediaReaction = mediaReaction
        }
    }
}

// MARK: - Press Conference Engine

enum PressConferenceEngine {

    // MARK: - Reporters

    private static let reporters: [(name: String, outlet: String)] = [
        ("Adam Schefter", "ESPN"),
        ("Ian Rapoport", "NFL Network"),
        ("Jay Glazer", "FOX Sports"),
        ("Josina Anderson", "CBS Sports"),
        ("Tom Pelissero", "NFL Network"),
        ("Diana Russini", "The Athletic"),
        ("Mike Garafolo", "NFL Network"),
        ("Albert Breer", "Sports Illustrated"),
    ]

    private static let localReporters: [(name: String, outlet: String)] = [
        ("Beat Reporter", "Local Press"),
        ("Staff Writer", "City Tribune"),
        ("Sports Desk", "Local News 9"),
    ]

    private static func randomReporter() -> (name: String, outlet: String) {
        reporters.randomElement() ?? reporters[0]
    }

    private static func randomLocalReporter() -> (name: String, outlet: String) {
        localReporters.randomElement() ?? localReporters[0]
    }

    // MARK: - Intro Press Conference

    /// Generate 4-5 questions for the introductory press conference.
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

        // Q5: Media pressure (large market only)
        if team.mediaMarket == .large {
            questions.append(generateMediaPressureQuestion(team: team))
        }

        return questions
    }

    // MARK: - Weekly Press Conference

    /// Generate 2-3 questions for a weekly in-season press conference.
    static func generateWeeklyPressConference(
        career: Career,
        team: Team,
        lastGameResult: Bool?,
        week: Int
    ) -> [PressQuestion] {
        var questions: [PressQuestion] = []

        // Post-game question
        if let won = lastGameResult {
            if won {
                questions.append(generatePostWinQuestion(team: team, week: week))
            } else {
                questions.append(generatePostLossQuestion(team: team, week: week))
            }
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

        // Occasional third question
        if Bool.random() {
            questions.append(generateLooseWeeklyQuestion(team: team))
        }

        return questions
    }

    // MARK: - Promise Evaluation

    /// Evaluate whether the player delivered on press conference promises.
    static func evaluateDelivery(
        career: Career,
        promises: [LegacyTracker.PressPromise]
    ) -> [LegacyTracker.LegacyAchievement] {
        var achievements: [LegacyTracker.LegacyAchievement] = []

        for promise in promises where promise.isDelivered == nil {
            // Check championship / parade promise — true high risk/high reward
            if promise.statement.lowercased().contains("championship") ||
               promise.statement.lowercased().contains("parade") ||
               promise.statement.lowercased().contains("super bowl") {
                if career.championships > 0 {
                    achievements.append(LegacyTracker.LegacyAchievement(
                        title: "Promise Keeper",
                        description: "You promised a championship and delivered.",
                        points: 20,
                        season: career.currentSeason
                    ))
                } else {
                    achievements.append(LegacyTracker.LegacyAchievement(
                        title: "Broken Promise",
                        description: "You promised a championship but fell short.",
                        points: -15,
                        season: career.currentSeason
                    ))
                }
            }

            // Check patience / process promise
            if promise.statement.lowercased().contains("process") ||
               promise.statement.lowercased().contains("patience") ||
               promise.statement.lowercased().contains("build") {
                if career.totalWins > career.totalLosses {
                    achievements.append(LegacyTracker.LegacyAchievement(
                        title: "The Process Works",
                        description: "You asked for patience and built a winner.",
                        points: 30,
                        season: career.currentSeason
                    ))
                }
            }
        }

        return achievements
    }

    // MARK: - Aggregate Results

    /// Build a `PressConferenceResult` from the questions and the indices the player chose.
    static func buildResult(
        questions: [PressQuestion],
        selectedIndices: [Int]
    ) -> PressConferenceResult {
        var selected: [PressConferenceResult.SelectedResponse] = []
        var total = PressEffects()
        var toneCounts: [ResponseTone: Int] = [:]
        var promises: [LegacyTracker.PressPromise] = []

        for (qi, si) in selectedIndices.enumerated() where qi < questions.count {
            let question = questions[qi]
            guard si < question.responses.count else { continue }
            let response = question.responses[si]

            selected.append(PressConferenceResult.SelectedResponse(
                questionSummary: question.question,
                responseText: response.text,
                tone: response.tone,
                mediaReaction: response.mediaReaction
            ))

            total = total + response.effects

            toneCounts[response.tone, default: 0] += 1

            // Track bold promises
            let lower = response.text.lowercased()
            if lower.contains("championship") || lower.contains("parade") || lower.contains("super bowl") {
                promises.append(LegacyTracker.PressPromise(
                    statement: response.text,
                    season: 0 // caller should set the real season
                ))
            }
            if lower.contains("process") || lower.contains("patience") || lower.contains("earn your support") {
                promises.append(LegacyTracker.PressPromise(
                    statement: response.text,
                    season: 0
                ))
            }
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

    private static func generateVisionQuestion(team: Team, owner: Owner) -> PressQuestion {
        let r = randomReporter()
        let ownerWinNow = owner.prefersWinNow

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "What's your vision for this franchise?",
            responses: [
                // Confident: Big legacy/fans upside, moderate risk if owner disagrees
                PressResponse(
                    text: "We're going to bring a championship to \(team.city). That's the only goal.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"Bold promise from the new front office leader!\"",
                    effects: PressEffects(
                        ownerSatisfaction: ownerWinNow ? 5 : -4,
                        playerMorale: -3,
                        mediaPerception: 5,
                        legacyPoints: 10,
                        fanExcitement: 12
                    )
                ),
                // Humble: Good for owner/media, fans disappointed
                PressResponse(
                    text: "First, I need to understand what we have. Then we build, brick by brick.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \"New leader takes measured approach in \(team.city).\"",
                    effects: PressEffects(
                        ownerSatisfaction: 8,
                        playerMorale: 2,
                        mediaPerception: 6,
                        legacyPoints: 2,
                        fanExcitement: -3
                    )
                ),
                // Aggressive: Huge media buzz, but tanks morale and risks owner
                PressResponse(
                    text: "This roster needs a complete overhaul. There are going to be a lot of changes.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"New GM already critical of \(team.name) roster!\"",
                    effects: PressEffects(
                        ownerSatisfaction: ownerWinNow ? -8 : 3,
                        playerMorale: -10,
                        mediaPerception: 18,
                        legacyPoints: 5,
                        fanExcitement: 3
                    )
                ),
                // Diplomatic: All small positives, no risk, no big reward
                PressResponse(
                    text: "There's talent here. We'll evaluate everything and add the right pieces.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \"Steady hand takes the reins in \(team.city).\"",
                    effects: PressEffects(
                        ownerSatisfaction: 2,
                        playerMorale: 2,
                        mediaPerception: 1,
                        legacyPoints: 1,
                        fanExcitement: 1
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
                // Confident: Big fan/legacy boost, risk with owner if cap is tight
                PressResponse(
                    text: "We'll be aggressive. You have to spend money to win in this league.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"\(team.name) expected to be big spenders this offseason.\"",
                    effects: PressEffects(
                        ownerSatisfaction: capTight ? -5 : 3,
                        playerMorale: 3,
                        mediaPerception: 4,
                        legacyPoints: 8,
                        fanExcitement: 12
                    )
                ),
                // Diplomatic: Small all-around positives
                PressResponse(
                    text: "The cap is a tool. We need to be smart, not reckless.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \"New front office preaches fiscal discipline.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 3,
                        playerMorale: 1,
                        mediaPerception: 2,
                        legacyPoints: 2,
                        fanExcitement: 1
                    )
                ),
                // Aggressive: Huge media splash, tanks morale and risks owner
                PressResponse(
                    text: "Some of these contracts are... let's just say I have a lot of work to do.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"Shots fired? New GM hints at roster purge.\"",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: -8,
                        mediaPerception: 18,
                        legacyPoints: 5,
                        fanExcitement: 3
                    )
                ),
                // Humble: Good for owner/media, fans bored
                PressResponse(
                    text: "I inherited a situation. I'll learn the books, then make my moves.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \"Patience is the word in \(team.city).\"",
                    effects: PressEffects(
                        ownerSatisfaction: 7,
                        playerMorale: 2,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: -3
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
                // Confident (parade route): TRUE high risk/high reward
                // +20 legacy if delivered (tracked via promise), big fan spike, but owner/morale risk
                PressResponse(
                    text: "Start planning the parade route.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"PARADE ROUTE?! New GM goes all-in on championship promise.\"",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: -3,
                        mediaPerception: 8,
                        legacyPoints: 20,
                        fanExcitement: 15
                    )
                ),
                // Humble: Good for owner/media, fans meh
                PressResponse(
                    text: "Trust the process. We're going to earn your support every single day.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \"New leadership asks fans for patience and trust.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 6,
                        playerMorale: 3,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: -3
                    )
                ),
                // Funny: Big fan boost, slight media credibility hit, good for locker room
                PressResponse(
                    text: "I promise -- the hot dogs at the stadium are going to be better this year.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \"LOL -- new GM wins over the press room with humor.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 1,
                        playerMorale: 5,
                        mediaPerception: -2,
                        legacyPoints: 1,
                        fanExcitement: 12
                    )
                ),
                // Diplomatic: Small all-around positives
                PressResponse(
                    text: "This is your team. I'm just here to make sure we give you something to cheer about.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \"Humble words from the new man in charge.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 2,
                        playerMorale: 2,
                        mediaPerception: 2,
                        legacyPoints: 1,
                        fanExcitement: 3
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
                // Confident: Big legacy/fan payoff, slight owner risk
                PressResponse(
                    text: "We're going to take the best player available. Period. No reaching.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"BPA philosophy for the new \(team.name) regime.\"",
                    effects: PressEffects(
                        ownerSatisfaction: -3,
                        playerMorale: 1,
                        mediaPerception: 4,
                        legacyPoints: 10,
                        fanExcitement: 8
                    )
                ),
                // Humble: Good for owner/media, fans disappointed
                PressResponse(
                    text: "I need to study the tape. I don't want to commit to a strategy before I've done my homework.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \"New GM wants to see film before making draft plans.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 1,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: -3
                    )
                ),
                // Aggressive: Big media splash, hurts morale and owner
                PressResponse(
                    text: "If we can trade back and stockpile picks, that's what we're doing. Quantity has a quality of its own.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"Trade-back strategy on the table for \(team.city).\"",
                    effects: PressEffects(
                        ownerSatisfaction: -6,
                        playerMorale: -7,
                        mediaPerception: 15,
                        legacyPoints: 5,
                        fanExcitement: -3
                    )
                ),
                // Diplomatic: All small positives
                PressResponse(
                    text: "The draft is how you build dynasties. We're going to nail this.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \"\(team.name) putting emphasis on the draft.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 2,
                        playerMorale: 2,
                        mediaPerception: 2,
                        legacyPoints: 1,
                        fanExcitement: 2
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
                // Confident: Big legacy/fans, slight owner/morale risk
                PressResponse(
                    text: "I thrive in it. The bigger the stage, the better I perform.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"Fearless attitude from the new front office boss.\"",
                    effects: PressEffects(
                        ownerSatisfaction: -3,
                        playerMorale: -3,
                        mediaPerception: 5,
                        legacyPoints: 12,
                        fanExcitement: 10
                    )
                ),
                // Aggressive: Very high media reward, clear negatives in owner/media relationship
                PressResponse(
                    text: "I don't read the papers. I just do my job.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"New GM seems uninterested in cozy media relationships.\"",
                    effects: PressEffects(
                        ownerSatisfaction: -5,
                        playerMorale: 5,
                        mediaPerception: -8,
                        legacyPoints: 15,
                        fanExcitement: 8
                    )
                ),
                // Diplomatic: Small all-around positives
                PressResponse(
                    text: "I respect the media. You have a job to do, and so do I. Let's work together.",
                    tone: .diplomatic,
                    mediaReaction: "\(r.outlet): \"Refreshing transparency from the new regime.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 2,
                        playerMorale: 1,
                        mediaPerception: 3,
                        legacyPoints: 1,
                        fanExcitement: 2
                    )
                ),
                // Funny: Big fan boost, slight media credibility hit, good for locker room
                PressResponse(
                    text: "Pressure? I've been under pressure my whole career. This is Tuesday for me.",
                    tone: .funny,
                    mediaReaction: "\(r.outlet): \"Ha! New GM keeps it cool under the bright lights.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 1,
                        playerMorale: 5,
                        mediaPerception: -3,
                        legacyPoints: 2,
                        fanExcitement: 15
                    )
                ),
            ]
        )
    }

    // MARK: - Weekly Question Generators

    private static func generatePostWinQuestion(team: Team, week: Int) -> PressQuestion {
        let r = randomReporter()

        return PressQuestion(
            reporterName: r.name,
            outlet: r.outlet,
            question: "Great win in Week \(week). What worked out there?",
            responses: [
                PressResponse(
                    text: "The guys executed the game plan perfectly. That's what happens when you prepare.",
                    tone: .confident,
                    mediaReaction: "\(r.outlet): \"\(team.name) clicking on all cylinders.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 10,
                        mediaPerception: 5,
                        legacyPoints: 1,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "Credit goes to the players and coaches. They put in the work all week.",
                    tone: .humble,
                    mediaReaction: "\(r.outlet): \"Humble leader deflects credit to the locker room.\"",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 15,
                        mediaPerception: 5,
                        legacyPoints: 2,
                        fanExcitement: 5
                    )
                ),
                PressResponse(
                    text: "We won but we left a lot on the table. We need to be better.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"Even after a win, \(team.name) boss demands more.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) leader falls on the sword after loss.\"",
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
                    mediaReaction: "\(r.outlet): \"Frustration mounting in the \(team.name) building.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) GM confident despite setback.\"",
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
                    mediaReaction: "\(r.outlet): \"United front in \(team.city) despite the loss.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) embracing the playoff spotlight.\"",
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
                    mediaReaction: "\(r.outlet): \"Steady as she goes for \(team.city).\"",
                    effects: PressEffects(
                        ownerSatisfaction: 5,
                        playerMorale: 5,
                        mediaPerception: 0,
                        legacyPoints: 1,
                        fanExcitement: 0
                    )
                ),
                PressResponse(
                    text: "Playoffs? I'm already thinking about the Super Bowl.",
                    tone: .aggressive,
                    mediaReaction: "\(r.outlet): \"SUPER BOWL?! \(team.name) GM looking past the competition?\"",
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
                    mediaReaction: "\(r.outlet): \"Shakeup looming in \(team.city)?\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) boss standing behind the roster.\"",
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
                    mediaReaction: "\(r.outlet): \"Patience remains the word in \(team.city).\"",
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
                    mediaReaction: "\(r.outlet): \"Business as usual for the \(team.name).\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) focused on details heading into next week.\"",
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
                    mediaReaction: "\(r.outlet): \"Ha -- good luck getting secrets out of this front office.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) locker room united, per sources.\"",
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
                    mediaReaction: "\(r.outlet): \"Good vibes in \(team.city) -- players enjoying the season.\"",
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
                    mediaReaction: "\(r.outlet): \"Tight-lipped approach from \(team.name) front office.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) boss expected nothing less than dominance.\"",
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
                    mediaReaction: "\(r.outlet): \"Selfless leadership fueling the \(team.name) surge.\"",
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
                    mediaReaction: "\(r.outlet): \"Even on a roll, \(team.name) front office wants more.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) insists the turnaround is coming.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) leader takes accountability amid losing streak.\"",
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
                    mediaReaction: "\(r.outlet): \"SHAKEUP? \(team.name) boss hints at major changes.\"",
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
                    mediaReaction: "\(r.outlet): \"Patience is the message in \(team.city) despite struggles.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) going for it at the trade deadline!\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) taking measured approach to deadline.\"",
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
                    mediaReaction: "\(r.outlet): \"FIRE SALE? \(team.name) open for business at the deadline.\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) keeping trade plans close to the vest.\"",
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
                    mediaReaction: "\(r.outlet): \"Championship or bust for the \(team.name)!\"",
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
                    mediaReaction: "\(r.outlet): \"\(team.name) taking it one step at a time.\"",
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
                    mediaReaction: "\(r.outlet): \"Confidence in \(team.city) as the new season kicks off.\"",
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
                        ? "\(r.outlet): \"\(team.name) ready for the postseason stage.\""
                        : "\(r.outlet): \"\(team.name) boss sees progress despite the record.\"",
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
                        ? "\(r.outlet): \"Focused mindset from \(team.city) heading into January.\""
                        : "\(r.outlet): \"\(team.name) leader vows to do better next year.\"",
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
                        ? "\(r.outlet): \"\(team.name) treating playoffs as their true stage.\""
                        : "\(r.outlet): \"Offseason overhaul incoming in \(team.city)?\"",
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
