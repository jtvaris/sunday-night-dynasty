import Foundation

// MARK: - Game Task Model

/// A single actionable task displayed in the Calendar sidebar.
struct GameTask: Identifiable, Codable, Equatable {
    let id: UUID
    let phase: SeasonPhase
    let title: String
    let description: String
    let icon: String          // SF Symbol name
    let destination: TaskDestination
    let isRequired: Bool
    var status: TaskStatus
    let weekAvailable: Int?   // nil = available entire phase

    init(
        phase: SeasonPhase,
        title: String,
        description: String,
        icon: String,
        destination: TaskDestination,
        isRequired: Bool,
        status: TaskStatus = .todo,
        weekAvailable: Int? = nil
    ) {
        self.id = UUID()
        self.phase = phase
        self.title = title
        self.description = description
        self.icon = icon
        self.destination = destination
        self.isRequired = isRequired
        self.status = status
        self.weekAvailable = weekAvailable
    }
}

enum TaskStatus: String, Codable {
    case todo
    case inProgress
    case done
}

enum TaskDestination: String, Codable, CaseIterable {
    case roster
    case depthChart
    case gamePlan
    case schedule
    case standings
    case coachingStaff
    case hireCoach
    case hireHC
    case hireOC
    case hireDC
    case scouting
    case prospectList
    case bigBoard
    case capOverview
    case freeAgency
    case contractTimeline
    case draft
    case mentoring
    case trades
    case news
    case ownerMeeting
    case lockerRoom
    case inbox
    case rosterEvaluation
    case franchiseTag
}

// MARK: - Task Generator

/// Stateless factory that produces phase-appropriate tasks based on career
/// and team state.
enum TaskGenerator {

    // MARK: - Phase Metadata

    struct PhaseInfo {
        let name: String
        let description: String
        let order: Int          // 1-based position in the season cycle
    }

    static let totalPhases = 14

    static func phaseInfo(for phase: SeasonPhase) -> PhaseInfo {
        switch phase {
        case .proBowl:
            return PhaseInfo(
                name: "Pro Bowl",
                description: "All-star festivities and end-of-season recognition.",
                order: 1
            )
        case .superBowl:
            return PhaseInfo(
                name: "Super Bowl",
                description: "The championship game caps off the season. Review results and league awards.",
                order: 2
            )
        case .coachingChanges:
            return PhaseInfo(
                name: "Coaching Changes",
                description: "Evaluate your coaching staff and fill any vacancies before the offseason ramps up.",
                order: 3
            )
        case .reviewRoster:
            return PhaseInfo(
                name: "Review Roster",
                description: "Evaluate your roster, apply franchise tags, and identify needs before free agency opens.",
                order: 4
            )
        case .combine:
            return PhaseInfo(
                name: "NFL Combine",
                description: "Prospects showcase their athletic ability. Scout, interview, and build your Big Board.",
                order: 5
            )
        case .freeAgency:
            return PhaseInfo(
                name: "Free Agency",
                description: "Re-sign your own players and pursue free agents to address roster needs.",
                order: 6
            )
        case .draft:
            return PhaseInfo(
                name: "NFL Draft",
                description: "Select the next generation of talent for your franchise.",
                order: 7
            )
        case .otas:
            return PhaseInfo(
                name: "OTAs",
                description: "Organize team activities, set your depth chart, and pair mentors with young players.",
                order: 8
            )
        case .trainingCamp:
            return PhaseInfo(
                name: "Training Camp",
                description: "Players compete for roster spots. Evaluate development and position battles.",
                order: 9
            )
        case .preseason:
            return PhaseInfo(
                name: "Preseason",
                description: "Exhibition games let you evaluate young talent before final roster decisions.",
                order: 10
            )
        case .rosterCuts:
            return PhaseInfo(
                name: "Roster Cuts",
                description: "Trim the roster to 53 players and set your practice squad.",
                order: 11
            )
        case .regularSeason:
            return PhaseInfo(
                name: "Regular Season",
                description: "Compete across 18 weeks for a playoff berth. Manage injuries, trades, and game plans.",
                order: 12
            )
        case .tradeDeadline:
            return PhaseInfo(
                name: "Trade Deadline",
                description: "Last chance to make trades this season. Buy or sell based on your record.",
                order: 13
            )
        case .playoffs:
            return PhaseInfo(
                name: "Playoffs",
                description: "Win or go home. Prepare your game plan and manage your roster for each round.",
                order: 14
            )
        }
    }

    // MARK: - Task Generation

    /// Generate a list of tasks for the given phase and game state.
    ///
    /// - Parameters:
    ///   - phase: The current season phase.
    ///   - career: The player's career model.
    ///   - team: The player's team (optional -- nil if not yet assigned).
    ///   - rosterCount: Number of players currently on the active roster.
    ///   - hasPendingTradeOffers: Whether unanswered trade offers exist.
    ///   - hasHeadCoach: Whether the team currently has a head coach.
    ///   - hasOC: Whether the team currently has an offensive coordinator.
    ///   - hasDC: Whether the team currently has a defensive coordinator.
    ///   - hasExpiringContracts: Whether any key players have expiring contracts.
    ///   - opponentName: The name of the next opponent (regular season / playoffs).
    ///   - playoffRoundName: The name of the current playoff round (e.g. "Divisional").
    ///   - hasScoutsAssigned: Whether any scouts are deployed on college scouting.
    ///   - hasPendingEvents: Whether there are unhandled game events / news items.
    ///   - ownerSatisfaction: The owner's current satisfaction rating.
    ///   - isDraftComplete: Whether the draft has already been completed this phase.
    /// - Returns: An ordered array of `GameTask` items.
    static func generateTasks(
        for phase: SeasonPhase,
        career: Career,
        team: Team?,
        rosterCount: Int = 53,
        hasPendingTradeOffers: Bool = false,
        hasHeadCoach: Bool = true,
        hasOC: Bool = true,
        hasDC: Bool = true,
        hasExpiringContracts: Bool = false,
        opponentName: String? = nil,
        playoffRoundName: String? = nil,
        hasScoutsAssigned: Bool = false,
        hasPendingEvents: Bool = false,
        ownerSatisfaction: Int = 50,
        isDraftComplete: Bool = false
    ) -> [GameTask] {
        switch phase {
        case .superBowl:
            return superBowlTasks()
        case .proBowl:
            return proBowlTasks()
        case .coachingChanges:
            return coachingChangesTasks(
                hasHeadCoach: hasHeadCoach,
                hasOC: hasOC,
                hasDC: hasDC,
                playerIsHC: career.role == .gmAndHeadCoach
            )
        case .combine:
            return combineTasks()
        case .freeAgency:
            return freeAgencyTasks(hasExpiringContracts: hasExpiringContracts)
        case .reviewRoster:
            return reviewRosterTasks()
        case .draft:
            return draftTasks(isDraftComplete: isDraftComplete)
        case .otas:
            return otasTasks()
        case .trainingCamp:
            return trainingCampTasks()
        case .preseason:
            return preseasonTasks()
        case .rosterCuts:
            return rosterCutsTasks(rosterCount: rosterCount)
        case .regularSeason:
            return regularSeasonTasks(
                opponentName: opponentName,
                hasPendingTradeOffers: hasPendingTradeOffers,
                hasScoutsAssigned: hasScoutsAssigned,
                hasPendingEvents: hasPendingEvents,
                ownerSatisfaction: ownerSatisfaction
            )
        case .tradeDeadline:
            return tradeDeadlineTasks(hasPendingTradeOffers: hasPendingTradeOffers)
        case .playoffs:
            return playoffTasks(
                playoffRoundName: playoffRoundName,
                opponentName: opponentName
            )
        }
    }

    // MARK: - Phase-Specific Task Lists

    private static func superBowlTasks() -> [GameTask] {
        [
            GameTask(
                phase: .superBowl,
                title: "Watch the Super Bowl results",
                description: "See which team won the championship and review the game recap.",
                icon: "trophy.fill",
                destination: .news,
                isRequired: false,
                status: .done  // auto-complete
            ),
            GameTask(
                phase: .superBowl,
                title: "Review league awards",
                description: "Check MVP, Offensive/Defensive Player of the Year, and other honors.",
                icon: "star.fill",
                destination: .news,
                isRequired: false,
                status: .done  // auto-complete
            ),
        ]
    }

    private static func proBowlTasks() -> [GameTask] {
        [
            GameTask(
                phase: .proBowl,
                title: "Review Pro Bowl selections",
                description: "See which of your players earned Pro Bowl honors.",
                icon: "star.circle.fill",
                destination: .roster,
                isRequired: false,
                status: .done  // auto-complete
            ),
        ]
    }

    private static func coachingChangesTasks(
        hasHeadCoach: Bool,
        hasOC: Bool,
        hasDC: Bool,
        playerIsHC: Bool = false
    ) -> [GameTask] {
        var tasks: [GameTask] = []

        // REQUIRED: individual coach hiring tasks
        // If player is GM+HC, they ARE the head coach — no need to hire one
        if !hasHeadCoach && !playerIsHC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Head Coach",
                description: "Your team has no head coach. Hire one before moving on.",
                icon: "person.badge.plus",
                destination: .hireHC,
                isRequired: true
            ))
        }

        if !hasOC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Offensive Coordinator",
                description: "Your team needs an offensive coordinator to run the offense.",
                icon: "person.badge.plus",
                destination: .hireOC,
                isRequired: true
            ))
        }

        if !hasDC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Defensive Coordinator",
                description: "Your team needs a defensive coordinator to run the defense.",
                icon: "person.badge.plus",
                destination: .hireDC,
                isRequired: true
            ))
        }

        // Optional: review and schemes
        tasks.append(GameTask(
            phase: .coachingChanges,
            title: "Review coaching staff",
            description: "Evaluate your coordinators and position coaches.",
            icon: "person.3.fill",
            destination: .coachingStaff,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .coachingChanges,
            title: "Review coordinator schemes",
            description: "Check offensive and defensive scheme fit with your roster.",
            icon: "gearshape.2.fill",
            destination: .coachingStaff,
            isRequired: false
        ))

        return tasks
    }

    private static func combineTasks() -> [GameTask] {
        [
            // REQUIRED: must visit scouting at least once
            GameTask(
                phase: .combine,
                title: "Review Combine results",
                description: "Check 40 times, bench press, and drill results for top prospects.",
                icon: "chart.bar.fill",
                destination: .scouting,
                isRequired: true
            ),
            // Optional
            GameTask(
                phase: .combine,
                title: "Send scouts to Combine",
                description: "Deploy your scouting staff to evaluate prospects in person.",
                icon: "binoculars.fill",
                destination: .scouting,
                isRequired: false
            ),
            GameTask(
                phase: .combine,
                title: "Update Big Board",
                description: "Rank prospects based on Combine performance and scouting reports.",
                icon: "list.number",
                destination: .bigBoard,
                isRequired: false
            ),
            GameTask(
                phase: .combine,
                title: "Conduct prospect interviews",
                description: "Meet with prospects to evaluate character, football IQ, and fit.",
                icon: "bubble.left.and.bubble.right.fill",
                destination: .prospectList,
                isRequired: false
            ),
        ]
    }

    private static func freeAgencyTasks(hasExpiringContracts: Bool) -> [GameTask] {
        var tasks: [GameTask] = []

        // REQUIRED: review free agent market
        tasks.append(GameTask(
            phase: .freeAgency,
            title: "Review free agent market",
            description: "Visit the free agency view to see available players.",
            icon: "person.2.fill",
            destination: .freeAgency,
            isRequired: true
        ))

        // REQUIRED: review expiring contracts / cap situation
        tasks.append(GameTask(
            phase: .freeAgency,
            title: "Review expiring contracts",
            description: "Check your salary cap and contract situations before spending.",
            icon: "dollarsign.circle.fill",
            destination: .capOverview,
            isRequired: true
        ))

        // Optional
        if hasExpiringContracts {
            tasks.append(GameTask(
                phase: .freeAgency,
                title: "Re-sign key players",
                description: "Lock up your core players before they test free agency.",
                icon: "signature",
                destination: .contractTimeline,
                isRequired: false
            ))
        }

        tasks.append(GameTask(
            phase: .freeAgency,
            title: "Sign free agents",
            description: "Make offers to free agents who fill your team's biggest needs.",
            icon: "person.badge.plus",
            destination: .freeAgency,
            isRequired: false
        ))

        return tasks
    }

    private static func reviewRosterTasks() -> [GameTask] {
        [
            GameTask(
                phase: .reviewRoster,
                title: "Review Position Group Grades",
                description: "Check which position groups need depth and which are strengths.",
                icon: "chart.bar.doc.horizontal",
                destination: .rosterEvaluation,
                isRequired: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Analyze Contract Situations",
                description: "Review expiring contracts, overpaid and underpaid players.",
                icon: "dollarsign.circle.fill",
                destination: .rosterEvaluation,
                isRequired: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Franchise Tag Decisions",
                description: "Apply franchise tag to keep key players from hitting free agency.",
                icon: "tag.fill",
                destination: .franchiseTag,
                isRequired: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Check Salary Cap Outlook",
                description: "Review cap space projections and budget for upcoming free agency.",
                icon: "chart.pie.fill",
                destination: .capOverview,
                isRequired: false
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Set Roster Priorities",
                description: "Identify your biggest needs heading into the draft.",
                icon: "list.bullet.clipboard.fill",
                destination: .rosterEvaluation,
                isRequired: false
            ),
        ]
    }

    private static func draftTasks(isDraftComplete: Bool) -> [GameTask] {
        var tasks: [GameTask] = [
            // REQUIRED: enter the draft
            GameTask(
                phase: .draft,
                title: "Enter the Draft",
                description: "It's time to select the future of your franchise.",
                icon: "list.clipboard.fill",
                destination: .draft,
                isRequired: true,
                status: isDraftComplete ? .done : .todo
            ),
            // Optional
            GameTask(
                phase: .draft,
                title: "Finalize Big Board",
                description: "Make final adjustments to your prospect rankings before draft day.",
                icon: "list.number",
                destination: .bigBoard,
                isRequired: false
            ),
            GameTask(
                phase: .draft,
                title: "Review team needs",
                description: "Check your depth chart for positions that need reinforcements.",
                icon: "chart.bar.doc.horizontal",
                destination: .depthChart,
                isRequired: false
            ),
        ]

        return tasks
    }

    private static func otasTasks() -> [GameTask] {
        [
            // REQUIRED: set depth chart
            GameTask(
                phase: .otas,
                title: "Set depth chart",
                description: "Establish your starting lineup and backup order at every position.",
                icon: "list.bullet.rectangle.portrait.fill",
                destination: .depthChart,
                isRequired: true
            ),
            // Optional
            GameTask(
                phase: .otas,
                title: "Set game plan",
                description: "Install your offensive and defensive schemes for the upcoming season.",
                icon: "sportscourt.fill",
                destination: .gamePlan,
                isRequired: false
            ),
            GameTask(
                phase: .otas,
                title: "Assign mentoring pairs",
                description: "Pair veteran leaders with young players to accelerate development.",
                icon: "person.2.wave.2.fill",
                destination: .mentoring,
                isRequired: false
            ),
        ]
    }

    private static func trainingCampTasks() -> [GameTask] {
        [
            // All optional
            GameTask(
                phase: .trainingCamp,
                title: "Review player development",
                description: "See which players improved during the offseason training program.",
                icon: "arrow.up.right.circle.fill",
                destination: .roster,
                isRequired: false
            ),
            GameTask(
                phase: .trainingCamp,
                title: "Evaluate roster battles",
                description: "Check position competitions and decide who earns a starting spot.",
                icon: "figure.wrestling",
                destination: .depthChart,
                isRequired: false
            ),
            GameTask(
                phase: .trainingCamp,
                title: "Check preseason storylines",
                description: "Read the latest news about your team heading into the preseason.",
                icon: "newspaper.fill",
                destination: .news,
                isRequired: false
            ),
        ]
    }

    private static func preseasonTasks() -> [GameTask] {
        [
            // All optional
            GameTask(
                phase: .preseason,
                title: "Watch preseason games",
                description: "Preseason games auto-simulate. Review results and stat lines.",
                icon: "play.rectangle.fill",
                destination: .schedule,
                isRequired: false,
                status: .done  // auto-simulated
            ),
            GameTask(
                phase: .preseason,
                title: "Evaluate young players",
                description: "Check preseason performance of rookies and fringe roster players.",
                icon: "person.crop.rectangle.stack.fill",
                destination: .roster,
                isRequired: false
            ),
        ]
    }

    private static func rosterCutsTasks(rosterCount: Int) -> [GameTask] {
        let overLimit = rosterCount > 53
        var tasks: [GameTask] = [
            // REQUIRED only if over 53
            GameTask(
                phase: .rosterCuts,
                title: overLimit
                    ? "Finalize 53-man roster (\(rosterCount) currently)"
                    : "Roster is at 53 players",
                description: overLimit
                    ? "You must release \(rosterCount - 53) player(s) to reach the 53-man limit."
                    : "Your roster meets the 53-man requirement.",
                icon: "scissors",
                destination: .roster,
                isRequired: overLimit,
                status: overLimit ? .todo : .done
            ),
        ]

        tasks.append(GameTask(
            phase: .rosterCuts,
            title: "Review practice squad",
            description: "Assign recently released players to your practice squad.",
            icon: "person.3.sequence.fill",
            destination: .roster,
            isRequired: false
        ))

        return tasks
    }

    private static func regularSeasonTasks(
        opponentName: String?,
        hasPendingTradeOffers: Bool,
        hasScoutsAssigned: Bool,
        hasPendingEvents: Bool,
        ownerSatisfaction: Int
    ) -> [GameTask] {
        // Regular season: no required tasks — advance always allowed
        var tasks: [GameTask] = []

        let opponent = opponentName ?? "your opponent"
        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Set game plan for \(opponent)",
            description: "Choose your offensive and defensive strategy for this week's matchup.",
            icon: "sportscourt.fill",
            destination: .gamePlan,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Review depth chart",
            description: "Make sure your best players are starting and backups are set.",
            icon: "list.bullet.rectangle.portrait.fill",
            destination: .depthChart,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Check injury report",
            description: "Review player injuries and adjust your lineup if needed.",
            icon: "cross.case.fill",
            destination: .roster,
            isRequired: false
        ))

        if hasScoutsAssigned {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Scout college prospects",
                description: "Your scouts have filed new reports. Review updated scouting intel.",
                icon: "binoculars.fill",
                destination: .scouting,
                isRequired: false
            ))
        }

        if hasPendingTradeOffers {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Review trade offers",
                description: "Other teams have proposed trades. Evaluate and respond.",
                icon: "arrow.left.arrow.right",
                destination: .trades,
                isRequired: false
            ))
        }

        if hasPendingEvents {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Handle pending events",
                description: "Important events need your attention before advancing.",
                icon: "exclamationmark.bubble.fill",
                destination: .news,
                isRequired: false
            ))
        }

        if ownerSatisfaction < 40 {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Owner meeting requested",
                description: "The owner is unhappy. Meet to discuss the team's direction.",
                icon: "building.2.fill",
                destination: .ownerMeeting,
                isRequired: false
            ))
        }

        return tasks
    }

    private static func tradeDeadlineTasks(hasPendingTradeOffers: Bool) -> [GameTask] {
        var tasks: [GameTask] = [
            GameTask(
                phase: .tradeDeadline,
                title: "Evaluate trade targets",
                description: "The deadline is approaching. Identify players who could help your team.",
                icon: "arrow.left.arrow.right",
                destination: .trades,
                isRequired: false
            ),
            GameTask(
                phase: .tradeDeadline,
                title: "Review roster and needs",
                description: "Decide whether to buy or sell at the deadline based on your record.",
                icon: "chart.bar.doc.horizontal",
                destination: .roster,
                isRequired: false
            ),
        ]

        if hasPendingTradeOffers {
            tasks.append(GameTask(
                phase: .tradeDeadline,
                title: "Respond to trade offers",
                description: "You have pending trade offers that expire at the deadline.",
                icon: "envelope.badge.fill",
                destination: .trades,
                isRequired: false
            ))
        }

        return tasks
    }

    private static func playoffTasks(
        playoffRoundName: String?,
        opponentName: String?
    ) -> [GameTask] {
        let round = playoffRoundName ?? "this round"
        let opponent = opponentName ?? "your opponent"

        return [
            GameTask(
                phase: .playoffs,
                title: "Prepare for \(round) vs \(opponent)",
                description: "Set your game plan for this win-or-go-home matchup.",
                icon: "sportscourt.fill",
                destination: .gamePlan,
                isRequired: false
            ),
            GameTask(
                phase: .playoffs,
                title: "Review matchups",
                description: "Compare your roster against the opponent's strengths and weaknesses.",
                icon: "person.2.fill",
                destination: .roster,
                isRequired: false
            ),
            GameTask(
                phase: .playoffs,
                title: "Check injury report",
                description: "Make sure your key players are healthy for the biggest stage.",
                icon: "cross.case.fill",
                destination: .roster,
                isRequired: false
            ),
        ]
    }

    // MARK: - Helpers

    /// Returns the count of incomplete required tasks.
    static func incompleteRequiredCount(in tasks: [GameTask]) -> Int {
        tasks.filter { $0.isRequired && $0.status != .done }.count
    }

    /// Returns true when all required tasks are marked done.
    static func allRequiredComplete(in tasks: [GameTask]) -> Bool {
        incompleteRequiredCount(in: tasks) == 0
    }
}
