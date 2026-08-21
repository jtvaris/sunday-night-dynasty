import Foundation

/// Stateless engine that generates contextual inbox messages for each season phase.
/// Inspired by Football Manager's email system -- messages come from the owner,
/// coordinators, scouts, media, and league office.
enum InboxEngine {

    // MARK: - Public API

    /// Generates phase-appropriate inbox messages based on the current game state.
    ///
    /// - Parameters:
    ///   - phase: The season phase that just became active.
    ///   - career: The player's career model.
    ///   - team: The player's current team.
    ///   - coaches: Coaches currently on the player's team.
    ///   - owner: The team's owner (if available).
    /// - Returns: An array of 2-5 inbox messages for the phase.
    static func generatePhaseMessages(
        phase: SeasonPhase,
        career: Career,
        team: Team,
        coaches: [Coach],
        owner: Owner?
    ) -> [InboxMessage] {
        let dateString = dateLabel(for: phase, career: career)
        let ownerName = owner?.name ?? "The Owner"
        let teamName = team.fullName

        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        switch phase {
        case .coachingChanges:
            return coachingChangesMessages(
                ownerName: ownerName, teamName: teamName,
                oc: oc, dc: dc, dateString: dateString
            )
        case .combine:
            return combineMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .freeAgency:
            return freeAgencyMessages(
                ownerName: ownerName, teamName: teamName,
                team: team, dateString: dateString
            )
        case .reviewRoster:
            return reviewRosterMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .proDays:
            return proDaysMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .draft:
            return draftMessages(
                ownerName: ownerName, teamName: teamName,
                oc: oc, dc: dc, dateString: dateString
            )
        case .otas:
            return otasMessages(
                ownerName: ownerName, teamName: teamName,
                oc: oc, dc: dc, dateString: dateString
            )
        case .trainingCamp:
            return trainingCampMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .preseason:
            return preseasonMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .rosterCuts:
            return rosterCutsMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        case .regularSeason:
            return regularSeasonMessages(
                career: career, teamName: teamName,
                oc: oc, dc: dc, dateString: dateString
            )
        case .superBowl:
            return superBowlMessages(
                ownerName: ownerName, dateString: dateString
            )
        case .proBowl:
            return proBowlMessages(dateString: dateString)
        case .playoffs:
            return playoffMessages(
                teamName: teamName, oc: oc, dc: dc, dateString: dateString
            )
        case .tradeDeadline:
            return tradeDeadlineMessages(
                ownerName: ownerName, teamName: teamName,
                dateString: dateString
            )
        }
    }

    // MARK: - Coaching Changes

    private static func coachingChangesMessages(
        ownerName: String, teamName: String,
        oc: Coach?, dc: Coach?,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        // Owner: roster analysis request
        messages.append(InboxMessage(
            sender: .owner(name: ownerName),
            subject: "Welcome -- Roster Assessment Needed",
            body: """
            Coach,

            I'd like your assessment of our current roster. Who are our key players? Where do we need to improve? Please review the team and let me know your thoughts.

            This is your franchise now. I trust your judgment, but I want to make sure we're aligned on the direction before the offseason really gets going.

            Take a look at the roster evaluation report and let's discuss.

            \(ownerName)
            """,
            date: dateString,
            category: .ownerDirective,
            actionRequired: true,
            actionDestination: .roster,
            attachments: [
                MessageAttachment(title: "View Roster Evaluation", destination: .roster)
            ]
        ))

        // OC assessment (if hired)
        if let oc = oc {
            let schemeName = oc.offensiveScheme?.rawValue ?? "our system"
            messages.append(InboxMessage(
                sender: .offensiveCoordinator(name: oc.fullName),
                subject: "Offensive Personnel Assessment",
                body: """
                Coach,

                I've been studying the film from last season and evaluating our offensive personnel. Here are my initial thoughts:

                QUARTERBACK: Our QB situation is the foundation of everything we do in the \(schemeName) system. I'll need to assess arm talent, decision-making speed, and pocket awareness.

                SKILL POSITIONS: I want to identify our top playmakers at WR, RB, and TE. We need guys who can create separation and make plays after the catch.

                OFFENSIVE LINE: This is where games are won and lost. I'm looking at our pass protection grades and run blocking consistency. Any weaknesses here need to be addressed early.

                I'll have a more detailed breakdown once I've had time with the full roster. Let me know if you want to discuss any specific positions.

                \(oc.fullName)
                Offensive Coordinator
                """,
                date: dateString,
                category: .staffUpdate,
                attachments: [
                    MessageAttachment(title: "View Depth Chart", destination: .depthChart)
                ]
            ))
        }

        // DC assessment (if hired)
        if let dc = dc {
            let schemeName = dc.defensiveScheme?.rawValue ?? "our scheme"
            messages.append(InboxMessage(
                sender: .defensiveCoordinator(name: dc.fullName),
                subject: "Defensive Personnel Assessment",
                body: """
                Coach,

                I've evaluated our defensive roster and here's what I see heading into the offseason:

                PASS RUSH: The most important thing in the \(schemeName) is generating pressure. I need to evaluate our edge rushers and interior pass rush. If we can't get to the quarterback, nothing else matters.

                SECONDARY: Our cornerbacks and safeties need to match up in coverage. I'm looking at their ball skills, recovery speed, and ability to play both man and zone.

                LINEBACKER CORPS: Our linebackers are the communication hub of the defense. I need smart, athletic players who can flow to the ball and drop into coverage when needed.

                I'll have more detailed evaluations after I've reviewed all the game tape. Looking forward to building something special on this side of the ball.

                \(dc.fullName)
                Defensive Coordinator
                """,
                date: dateString,
                category: .staffUpdate,
                attachments: [
                    MessageAttachment(title: "View Roster", destination: .roster)
                ]
            ))
        }

        // League welcome
        messages.append(InboxMessage(
            sender: .leagueOffice,
            subject: "Welcome to the \(teamName)",
            body: """
            Coach,

            On behalf of the league office, welcome to the \(teamName). Here are the key offseason dates you should be aware of:

            - COACHING CHANGES: Fill any remaining staff vacancies
            - THE COMBINE: Evaluate draft prospects and athletic testing
            - FREE AGENCY: Sign free agents and manage your salary cap
            - THE DRAFT: Select the next generation of talent
            - OTAs: Set your depth chart and install schemes
            - TRAINING CAMP: Evaluate roster battles and player development
            - PRESEASON: Exhibition games for final evaluations
            - ROSTER CUTS: Trim to 53 players

            Best of luck this season.

            League Office
            """,
            date: dateString,
            category: .leagueNotice
        ))

        return messages
    }

    // MARK: - Combine

    private static func combineMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        // Scout report
        messages.append(InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Combine Results Are In",
            body: """
            Coach,

            The combine results are in, and there are some impressive athletes in this year's class. I've compiled the testing data and cross-referenced it with our game film evaluations.

            A few things jumped out:

            - Several prospects at positions of need tested exceptionally well
            - There are some potential risers who weren't on many radar screens before the combine
            - A few highly-rated prospects underwhelmed in testing, which could create value in the draft

            I'd recommend reviewing the full scouting reports and beginning to shape our big board. The combine is just one piece of the puzzle, but it's an important one.

            I'll be available to discuss any prospects you want to take a closer look at.

            Scouting Department
            """,
            date: dateString,
            category: .scoutingReport,
            actionRequired: true,
            actionDestination: .scouting,
            attachments: [
                MessageAttachment(title: "View Scouting Hub", destination: .scouting),
                MessageAttachment(title: "Update Big Board", destination: .bigBoard)
            ]
        ))

        // Media projection
        let mockPositions = ["quarterback", "pass rusher", "offensive tackle", "wide receiver", "cornerback"]
        let projectedPosition = mockPositions.randomElement() ?? "quarterback"
        messages.append(InboxMessage(
            sender: .media(outlet: "League Network"),
            subject: "Mock Draft: \(teamName) Projected to Select...",
            body: """
            In our latest mock draft, national analysts are projecting the \(teamName) to select a \(projectedPosition) in the first round.

            "This team has a clear need at \(projectedPosition), and with the talent available in this class, they'd be smart to address it early," said our lead draft analyst.

            Of course, mock drafts are just projections. The combine can shake things up, and teams often go in unexpected directions on draft day.

            League Network Draft Coverage
            """,
            date: dateString,
            category: .mediaRequest
        ))

        // Owner check-in
        messages.append(InboxMessage(
            sender: .owner(name: ownerName),
            subject: "Combine Impressions?",
            body: """
            Coach,

            I watched some of the combine coverage. Any prospects catch your eye? I want to make sure we're doing our due diligence before the draft.

            Keep me posted on how the scouting is going.

            \(ownerName)
            """,
            date: dateString,
            category: .ownerDirective
        ))

        return messages
    }

    // MARK: - Free Agency

    private static func freeAgencyMessages(
        ownerName: String, teamName: String,
        team: Team, dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        let capSpace = formatCap(team.availableCap)

        // Owner spending question
        messages.append(InboxMessage(
            sender: .owner(name: ownerName),
            subject: "Free Agency Budget",
            body: """
            Coach,

            Free agency is about to open. We have \(capSpace) in available cap space. How much are we planning to spend, and what positions are we targeting?

            I want to be smart with our money, but I also want to compete. Let's make sure we have a clear plan before the market opens.

            \(ownerName)
            """,
            date: dateString,
            category: .ownerDirective,
            actionRequired: true,
            actionDestination: .freeAgency,
            attachments: [
                MessageAttachment(title: "View Free Agent Market", destination: .freeAgency),
                MessageAttachment(title: "Review Salary Cap", destination: .capOverview)
            ]
        ))

        // Agent reaching out. Drawn from `AgentPersona.agentNamePool` — the
        // single invented-agent pool the anonymization gate checks — rather than
        // a local list. The list that used to live here named five real,
        // currently-working NFL player agents.
        let agentName = AgentPersona.randomAgentName()
        messages.append(InboxMessage(
            sender: .playerAgent(name: agentName),
            subject: "Client Interested in \(teamName)",
            body: """
            Coach,

            I represent several free agents who have expressed interest in joining the \(teamName). My clients are looking for a competitive situation with a coaching staff they believe in.

            I'd love to set up a conversation about how my clients might fit into your system. There are some real difference-makers available this year, and I think we could find a deal that works for both sides.

            Let me know when you'd like to talk.

            \(agentName)
            Sports Agent
            """,
            date: dateString,
            category: .contractRequest,
            attachments: [
                MessageAttachment(title: "Browse Free Agents", destination: .freeAgency)
            ]
        ))

        // League notice
        messages.append(InboxMessage(
            sender: .leagueOffice,
            subject: "Free Agency Rules Reminder",
            body: """
            A reminder to all teams: the free agency period is now open. All contract offers must comply with the salary cap, and teams are responsible for managing their cap space accordingly.

            Teams that exceed the salary cap will be subject to penalties.

            League Office
            """,
            date: dateString,
            category: .leagueNotice
        ))

        return messages
    }

    // MARK: - Review Roster

    private static func reviewRosterMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        messages.append(InboxMessage(
            sender: .leagueOffice,
            subject: "Time to evaluate your roster",
            body: "Before the draft, take a close look at your roster. Review position group grades, contract situations, and salary cap outlook. Identifying your biggest needs now will shape your draft strategy.",
            date: dateString,
            category: .rosterAnalysis
        ))

        messages.append(InboxMessage(
            sender: .owner(name: ownerName),
            subject: "Roster evaluation period begins",
            body: "With free agency behind us, this is the perfect time to assess where we stand. Grade every position group, review who's overpaid or underpaid, and set priorities heading into the draft.",
            date: dateString,
            category: .ownerDirective
        ))

        return messages
    }

    // MARK: - Pro Days

    private static func proDaysMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        messages.append(InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Pro Day Schedule Available",
            body: """
                The college pro day schedule is set. Our scouts are ready to attend \
                key pro days to get a closer look at top prospects in their home \
                environment. Assign scouts to prioritize the most important visits.
                """,
            date: dateString,
            category: .draftPrep,
            attachments: [
                MessageAttachment(title: "View Scouting", destination: .scouting)
            ]
        ))

        return messages
    }

    // MARK: - Draft

    private static func draftMessages(
        ownerName: String, teamName: String,
        oc: Coach?, dc: Coach?,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        // Scout: final big board
        messages.append(InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Final Big Board Ready",
            body: """
            Coach,

            The final big board is ready. We've completed our evaluations, cross-referenced combine data with game film, and incorporated our in-person interviews.

            My top prospects for our needs are ranked and ready for your review. I feel good about the work we've done this draft cycle. There's real talent available that can help this team.

            Remember, the draft is about finding players who fit our system and culture. Don't just chase the best athlete -- find the right fit.

            Scouting Department
            """,
            date: dateString,
            category: .draftPrep,
            actionRequired: true,
            actionDestination: .draft,
            attachments: [
                MessageAttachment(title: "View Big Board", destination: .bigBoard),
                MessageAttachment(title: "Enter the Draft", destination: .draft)
            ]
        ))

        // OC recommendation
        if let oc = oc {
            let offPositions = ["QB", "WR", "OT", "RB", "TE"]
            let need = offPositions.randomElement() ?? "WR"
            messages.append(InboxMessage(
                sender: .offensiveCoordinator(name: oc.fullName),
                subject: "Draft Day Recommendations (Offense)",
                body: """
                Coach,

                With our pick, I'd love to see us address \(need). That's our biggest offensive need, and there are some really talented prospects available at that position.

                Here's my thinking: a dynamic \(need) would instantly elevate what we can do schematically. I've identified a few guys on the board who I think would be perfect fits for our system.

                Of course, you make the final call. But if a top \(need) is there when we pick, I think it's the right move.

                \(oc.fullName)
                """,
                date: dateString,
                category: .draftPrep
            ))
        }

        // DC recommendation
        if let dc = dc {
            let defPositions = ["EDGE", "CB", "DT", "LB", "S"]
            let need = defPositions.randomElement() ?? "EDGE"
            messages.append(InboxMessage(
                sender: .defensiveCoordinator(name: dc.fullName),
                subject: "Draft Day Recommendations (Defense)",
                body: """
                Coach,

                I think our biggest defensive need is \(need). If we can add a difference-maker at that position, it changes the entire complexion of our defense.

                I've watched the film on several \(need) prospects in this class, and there are a few guys who have the traits I'm looking for. Length, athleticism, and football IQ.

                I'd be happy to discuss any specific prospects with you before we go on the clock.

                \(dc.fullName)
                """,
                date: dateString,
                category: .draftPrep
            ))
        }

        return messages
    }

    // MARK: - OTAs

    private static func otasMessages(
        ownerName: String, teamName: String,
        oc: Coach?, dc: Coach?,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        if let oc = oc {
            messages.append(InboxMessage(
                sender: .offensiveCoordinator(name: oc.fullName),
                subject: "OTA Offensive Install Plan",
                body: """
                Coach,

                OTAs are a critical time for us to install the offensive system and get our guys comfortable with the playbook. I'm excited to work with the new additions and see how they fit.

                Priorities for OTAs:
                - Install base offensive concepts and terminology
                - Evaluate new acquisitions in live team periods
                - Identify our best offensive personnel groupings
                - Begin developing red zone and two-minute packages

                I'll need the depth chart finalized so we can structure practice reps accordingly.

                \(oc.fullName)
                """,
                date: dateString,
                category: .staffUpdate,
                attachments: [
                    MessageAttachment(title: "Set Depth Chart", destination: .depthChart)
                ]
            ))
        }

        if let dc = dc {
            messages.append(InboxMessage(
                sender: .defensiveCoordinator(name: dc.fullName),
                subject: "OTA Defensive Install Plan",
                body: """
                Coach,

                I'm looking forward to getting our defensive players on the field together for OTAs. We have some pieces to work with, and I want to see how our new additions mesh with the veterans.

                My focus areas:
                - Defensive alignment and assignment clarity
                - Communication between the secondary and front seven
                - Blitz package installation
                - Third-down and situational defense

                Let me know once the depth chart is set so I can plan our practice structure.

                \(dc.fullName)
                """,
                date: dateString,
                category: .staffUpdate,
                attachments: [
                    MessageAttachment(title: "Set Depth Chart", destination: .depthChart)
                ]
            ))
        }

        messages.append(InboxMessage(
            sender: .leagueOffice,
            subject: "OTA Rules and Schedule",
            body: """
            All teams are reminded that OTAs are voluntary for players, though full participation is strongly encouraged. Contact drills are not permitted during this phase.

            Use this time wisely to install your playbook and evaluate your roster.

            League Office
            """,
            date: dateString,
            category: .leagueNotice
        ))

        return messages
    }

    // MARK: - Training Camp

    private static func trainingCampMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .owner(name: ownerName),
                subject: "Training Camp Expectations",
                body: """
                Coach,

                Training camp is where teams are built. I expect us to come out of camp with a clear identity and a roster that's ready to compete.

                Work the young guys hard. I want to see which ones can handle the pressure. And keep an eye on any veterans who might be losing a step -- we can't afford to carry passengers.

                \(ownerName)
                """,
                date: dateString,
                category: .ownerDirective
            ),
            InboxMessage(
                sender: .media(outlet: "National Sports Network"),
                subject: "Training Camp Preview: \(teamName)",
                body: """
                Our training camp preview series continues with a look at the \(teamName). Key storylines to watch:

                - How will the new additions integrate with the existing roster?
                - Which position battles will shape the 53-man roster?
                - Can the coaching staff get the most out of this talent?

                We'll be tracking developments throughout camp and providing daily updates.

                National Sports Network Coverage
                """,
                date: dateString,
                category: .mediaRequest
            ),
            InboxMessage(
                sender: .scout(name: "Director of Scouting"),
                subject: "Camp Standouts to Watch",
                body: """
                Coach,

                Here are a few players I'd keep an eye on during camp:

                - Our rookie draft picks are eager to prove themselves. Watch for their development trajectory.
                - Several UDFAs have the athletic profiles to surprise people. Give them a fair shot.
                - A couple of veterans on the roster bubble could benefit from a strong camp performance.

                I'll be at practice every day taking notes and providing updates.

                Scouting Department
                """,
                date: dateString,
                category: .scoutingReport,
                attachments: [
                    MessageAttachment(title: "View Roster", destination: .roster)
                ]
            )
        ]
    }

    // MARK: - Preseason

    private static func preseasonMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .media(outlet: "Continental Sports"),
                subject: "Preseason Predictions: Where Does \(teamName) Rank?",
                body: """
                As preseason games get underway, our analysts have released their initial predictions for the upcoming season.

                The \(teamName) are generating buzz, but preseason games are about evaluation, not results. Smart coaches use this time to make final roster decisions and fine-tune their schemes.

                Continental Sports Coverage
                """,
                date: dateString,
                category: .mediaRequest
            ),
            InboxMessage(
                sender: .leagueOffice,
                subject: "Preseason Schedule Reminder",
                body: """
                Preseason games are scheduled. Remember, these games are auto-simulated and serve as final evaluation opportunities before roster cuts.

                Teams should use preseason to evaluate young players, test depth, and finalize game-day rosters.

                League Office
                """,
                date: dateString,
                category: .leagueNotice
            )
        ]
    }

    // MARK: - Roster Cuts

    private static func rosterCutsMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .owner(name: ownerName),
                subject: "Roster Decisions Due",
                body: """
                Coach,

                It's time to finalize the 53-man roster. These are some of the hardest decisions we'll make all year, but they have to be made.

                Be ruthless. Keep the 53 players who give us the best chance to win. If a guy doesn't fit, move on -- someone else will.

                \(ownerName)
                """,
                date: dateString,
                category: .ownerDirective,
                actionRequired: true,
                actionDestination: .roster,
                attachments: [
                    MessageAttachment(title: "Manage Roster", destination: .roster)
                ]
            ),
            InboxMessage(
                sender: .leagueOffice,
                subject: "53-Man Roster Deadline",
                body: """
                All teams must reduce their rosters to 53 players before advancing to the regular season. Players released during this period will be subject to waiver claims.

                League Office
                """,
                date: dateString,
                category: .leagueNotice
            )
        ]
    }

    // MARK: - Regular Season

    private static func regularSeasonMessages(
        career: Career, teamName: String,
        oc: Coach?, dc: Coach?,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        if let oc = oc {
            messages.append(InboxMessage(
                sender: .offensiveCoordinator(name: oc.fullName),
                subject: "Game Plan Ready (Offense)",
                body: """
                Coach,

                I've put together the offensive game plan for this week. I've studied the opponent's defensive tendencies and I think we can exploit some weaknesses.

                Key points:
                - Their pass defense has been vulnerable to quick-rhythm throws
                - We should be able to establish the run game early
                - Red zone efficiency will be critical -- we need touchdowns, not field goals

                Review the game plan when you get a chance. Let me know if you want any adjustments.

                \(oc.fullName)
                """,
                date: dateString,
                category: .gamePrep,
                attachments: [
                    MessageAttachment(title: "Set Game Plan", destination: .gamePlan)
                ]
            ))
        }

        if let dc = dc {
            messages.append(InboxMessage(
                sender: .defensiveCoordinator(name: dc.fullName),
                subject: "Game Plan Ready (Defense)",
                body: """
                Coach,

                I've broken down the opponent's offensive film. Here's what we're seeing:

                - Their offense relies heavily on their top playmaker -- we need to take him out of the game
                - Their offensive line has some pass protection issues we can exploit with pressure
                - We need to be disciplined against misdirection and play-action

                I feel good about our matchups this week. Let's go out and play fast.

                \(dc.fullName)
                """,
                date: dateString,
                category: .gamePrep,
                attachments: [
                    MessageAttachment(title: "Set Game Plan", destination: .gamePlan)
                ]
            ))
        }

        // Media press conference
        messages.append(InboxMessage(
            sender: .media(outlet: "Local Media"),
            subject: "Weekly Press Conference Reminder",
            body: """
            Coach,

            You've been asked to attend the weekly press conference. Reporters will have questions about the upcoming matchup, injury updates, and team performance.

            Your responses can affect team morale and public perception. Choose your words carefully.

            Media Relations Department
            """,
            date: dateString,
            category: .mediaRequest
        ))

        return messages
    }

    // MARK: - The Championship

    private static func superBowlMessages(
        ownerName: String, dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .leagueOffice,
                subject: "Championship Results",
                body: """
                The Championship has been played. Review the results and league awards as we transition into the offseason.

                Congratulations to all teams on a competitive season.

                League Office
                """,
                date: dateString,
                category: .leagueNotice
            ),
            InboxMessage(
                sender: .owner(name: ownerName),
                subject: "Season Wrap-Up",
                body: """
                Coach,

                Another season is in the books. Let's take stock of where we are and start planning for the offseason. There will be important decisions to make in the weeks ahead.

                \(ownerName)
                """,
                date: dateString,
                category: .ownerDirective
            )
        ]
    }

    // MARK: - All-Star Game

    private static func proBowlMessages(dateString: String) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .leagueOffice,
                subject: "All-Star Selections Announced",
                body: """
                The All-Star rosters have been announced. Check your roster to see if any of your players earned this recognition.

                All-Star selections are a testament to individual excellence and reflect well on the coaching staff.

                League Office
                """,
                date: dateString,
                category: .leagueNotice
            )
        ]
    }

    // MARK: - Playoffs

    private static func playoffMessages(
        teamName: String,
        oc: Coach?, dc: Coach?,
        dateString: String
    ) -> [InboxMessage] {
        var messages: [InboxMessage] = []

        if let oc = oc {
            messages.append(InboxMessage(
                sender: .offensiveCoordinator(name: oc.fullName),
                subject: "Playoff Game Plan (Offense)",
                body: """
                Coach,

                This is win or go home. I've put extra hours into this game plan. Every detail matters in the playoffs.

                The intensity level goes up, and we need to be at our sharpest. I've identified the key matchups we need to win on offense. Let's leave it all on the field.

                \(oc.fullName)
                """,
                date: dateString,
                category: .gamePrep,
                attachments: [
                    MessageAttachment(title: "Set Game Plan", destination: .gamePlan)
                ]
            ))
        }

        if let dc = dc {
            messages.append(InboxMessage(
                sender: .defensiveCoordinator(name: dc.fullName),
                subject: "Playoff Game Plan (Defense)",
                body: """
                Coach,

                Playoff football is about defense. I've put together our most detailed game plan of the season. We know exactly what they want to do, and we're going to take it away.

                The preparation has been outstanding. Our guys are ready. Let's go win this game.

                \(dc.fullName)
                """,
                date: dateString,
                category: .gamePrep,
                attachments: [
                    MessageAttachment(title: "Set Game Plan", destination: .gamePlan)
                ]
            ))
        }

        messages.append(InboxMessage(
            sender: .media(outlet: "National Sports Network"),
            subject: "Playoff Spotlight on \(teamName)",
            body: """
            The \(teamName) are in the playoffs, and all eyes are on the coaching staff. How will they handle the pressure of win-or-go-home football?

            Our analysts will be covering every angle of this matchup.

            National Sports Network Playoffs
            """,
            date: dateString,
            category: .mediaRequest
        ))

        return messages
    }

    // MARK: - Trade Deadline

    /// Delivered once, when the career ENTERS the deadline week (end of the
    /// previous advance), so "the deadline is approaching" is still true and the
    /// user has the whole week to act. Dead code until the phase became real —
    /// plan finding S2.
    private static func tradeDeadlineMessages(
        ownerName: String, teamName: String,
        dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .owner(name: ownerName),
                subject: "Trade Deadline Approaching",
                body: """
                Coach,

                The trade deadline is approaching. Are we buyers or sellers? Based on our record, I want to make sure we're making the right moves for this franchise.

                If there's a deal out there that can help us this year without mortgaging the future, I'm open to it. Let's talk.

                \(ownerName)
                """,
                date: dateString,
                category: .ownerDirective,
                attachments: [
                    MessageAttachment(title: "Explore Trades", destination: .trades)
                ]
            ),
            InboxMessage(
                sender: .scout(name: "Director of Scouting"),
                subject: "Trade Deadline Targets",
                body: """
                Coach,

                I've identified several players around the league who might be available before the deadline. Some teams are clearly in sell mode, and we might be able to find a deal that helps us.

                Let me know if you want me to focus on any specific positions or players.

                Scouting Department
                """,
                date: dateString,
                category: .tradeOffer,
                attachments: [
                    MessageAttachment(title: "View Trade Market", destination: .trades)
                ]
            )
        ]
    }

    /// The league office confirming that unanswered offers died with the deadline.
    ///
    /// `WeekAdvancer` has always wiped `career.pendingTradeOffers` when the
    /// deadline passed, silently — an offer the user was still thinking about just
    /// disappeared from the Trade Center (plan finding S2). Now the wipe leaves a
    /// receipt.
    static func tradeOffersExpiredMessage(
        count: Int,
        week: Int,
        season: Int
    ) -> InboxMessage {
        let plural = count == 1 ? "offer" : "offers"
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Trade deadline passed — \(count) \(plural) expired",
            body: """
            The trade deadline has passed. \(count) outstanding \(plural) on your desk \(count == 1 ? "was" : "were") withdrawn and no further trades can be completed until the season ends.

            Any deal you still want to make waits for the offseason.

            League Office
            """,
            date: "Week \(week), Season \(season)",
            category: .leagueNotice
        )
    }

    // MARK: - Trade Wire (Wave 2 — `docs/TRADE_OVERHAUL_PLAN.md`)

    /// Receipt for a trade the user's franchise was part of, whoever proposed it.
    ///
    /// Lives here rather than in `TradeNewsFactory` because this file is the
    /// authority on inbox copy — the factory formats the asset lists and hands
    /// them over. Category `.tradeOffer` (displayed as "Trade") is the existing
    /// bucket for trade mail; no new `MessageCategory` was needed.
    static func tradeCompletedMessage(
        partnerName: String,
        partnerAbbr: String,
        weReceive: String,
        weSend: String,
        dateString: String,
        wasOurProposal: Bool
    ) -> InboxMessage {
        let opening = wasOurProposal
            ? "The deal you put on the table with \(partnerName) is done."
            : "\(partnerName) came to us, and the deal is done."
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Trade completed with \(partnerAbbr)",
            body: """
            \(opening)

            We receive: \(weReceive)
            We send: \(weSend)

            Roster and cap adjustments have been processed. The transaction is final.

            League Office
            """,
            date: dateString,
            category: .tradeOffer,
            actionDestination: .roster
        )
    }

    /// Wire note for a trade the user was NOT part of but should hear about — a
    /// star changing teams, first-round capital moving, or a division rival
    /// making a move.
    ///
    /// WHY it exists: AI-vs-AI deals used to happen in total silence (plan
    /// finding S5/S7), so the league felt frozen even when players were moving.
    /// A rival's move is management information, not flavour text.
    static func leagueTradeWireMessage(
        headline: String,
        detail: String,
        dateString: String,
        isDivisionRival: Bool
    ) -> InboxMessage {
        let lead = isDivisionRival
            ? "A division rival just made a move. We should expect questions about how we answer it."
            : "Worth your attention — this one moves the balance of power."
        return InboxMessage(
            sender: .media(outlet: "League Trade Wire"),
            subject: headline,
            body: """
            \(lead)

            \(detail)
            """,
            date: dateString,
            category: .leagueNotice,
            actionDestination: .news
        )
    }

    // MARK: - Negotiation Threads (Wave 3 — `docs/TRADE_OVERHAUL_PLAN.md` §6)

    /// The GM hanging up for the rest of the league year.
    ///
    /// Wave 2 already made the freeze-out real (`TradeTalkRegistry` strikes, and
    /// `hardBlocker` refusing to price anything for a locked GM) but it only
    /// ever surfaced as a rejection string inside one alert. A relationship
    /// ending is mail — the same way a contract break-off ends up in the user's
    /// face rather than in a toast.
    static func tradeTalksBrokenOffMessage(
        gmName: String,
        partnerName: String,
        partnerAbbr: String,
        dateString: String
    ) -> InboxMessage {
        InboxMessage(
            sender: .leagueOffice,
            subject: "\(partnerAbbr) have ended trade talks",
            body: """
            \(gmName) called to say the \(partnerName) are done discussing trades with us for the rest of this league year.

            His front office logged one lowball too many from our side. Nothing we send them will be priced until the new league year resets the relationship.

            League Office
            """,
            date: dateString,
            category: .tradeOffer,
            actionDestination: .trades
        )
    }

    /// Open conversations that died when the window closed underneath them.
    ///
    /// The stored-offer equivalent (`tradeOffersExpiredMessage`) already exists;
    /// a thread the user was three rounds into is worth at least the same
    /// receipt, otherwise it simply vanishes from the Trade Center.
    static func tradeNegotiationsExpiredMessage(
        count: Int,
        dateString: String
    ) -> InboxMessage {
        let plural = count == 1 ? "negotiation" : "negotiations"
        return InboxMessage(
            sender: .leagueOffice,
            subject: "\(count) trade \(plural) closed out",
            body: """
            \(count) open trade \(plural) on our desk \(count == 1 ? "was" : "were") closed out — the assets involved have moved, or the window they were being worked in has shut.

            Anything we still want to chase has to start as a fresh conversation.

            League Office
            """,
            date: dateString,
            category: .tradeOffer,
            actionDestination: .trades
        )
    }

    // MARK: - Practice Squad (TODO §5.1)

    /// A rival has filed interest in one of our squad players — the one piece
    /// of mail in this file with a deadline attached.
    ///
    /// WHY the warning exists at all: a practice-squad signing is unblockable
    /// by rule, so the only counter-move a club has is to promote the player to
    /// its own 53 first. Landing the signing without notice would make that
    /// decision invisible; landing it a week later makes it a real one.
    static func practiceSquadPoachWarningMessage(
        playerName: String,
        position: String,
        suitorName: String,
        suitorAbbr: String,
        dateString: String
    ) -> InboxMessage {
        InboxMessage(
            sender: .developmentStaff,
            subject: "\(suitorAbbr) are circling \(playerName)",
            body: """
            The \(suitorName) have asked to work out our practice-squad \(position) \(playerName). That is how these things start.

            We cannot block it — any club may sign another club's squad player straight to its active roster, and he does not need our permission to take the raise. The only way to keep him is to promote him ourselves before they act, which costs us an active-roster spot and puts him on a first-team salary.

            If we do nothing, expect them to sign him within the week.

            Player Development
            """,
            date: dateString,
            category: .rosterAnalysis,
            actionRequired: true,
            actionDestination: .roster
        )
    }

    /// The receipt for a squad player another club signed away from us.
    static func practiceSquadPoachedMessage(
        playerName: String,
        position: String,
        suitorName: String,
        suitorAbbr: String,
        dateString: String
    ) -> InboxMessage {
        InboxMessage(
            sender: .leagueOffice,
            subject: "\(suitorAbbr) sign \(playerName) off our practice squad",
            body: """
            The \(suitorName) have signed \(position) \(playerName) to their active roster off our practice squad. The move is processed and final — there is no compensation and no right of refusal.

            His squad spot is open. Development flagged him as one we had time invested in.

            League Office
            """,
            date: dateString,
            category: .rosterAnalysis,
            actionDestination: .roster
        )
    }

    // MARK: - Draft Cycle Digests

    /// The one weekly note that says what a season of regional scouting is
    /// actually buying.
    ///
    /// Weeks 10-18 file 3-6 reports per scout and silently rewrite grades on the
    /// board; before this, the only way to notice was to open the prospect list
    /// and compare it against a memory of last week. One batched message per
    /// week — never one per report — and nothing at all on a week that changed
    /// nothing.
    static func weeklyScoutingDigestMessage(
        digest: ScoutingEngine.WeeklyScoutingDigest,
        season: Int
    ) -> InboxMessage {
        var subject = "Scouting: \(digest.reportCount) new report\(digest.reportCount == 1 ? "" : "s")"
        if digest.bandsNarrowed > 0 {
            subject += " — \(digest.bandsNarrowed) grade band\(digest.bandsNarrowed == 1 ? "" : "s") narrowed"
        }

        var lines: [String] = [
            "Coach,",
            "",
            "This week's regional work: \(digest.reportCount) report\(digest.reportCount == 1 ? "" : "s") filed on \(digest.prospectsCovered) prospect\(digest.prospectsCovered == 1 ? "" : "s")."
        ]
        if digest.firstLooks > 0 {
            lines.append("- \(digest.firstLooks) name\(digest.firstLooks == 1 ? "" : "s") we had never put eyes on before.")
        }
        if digest.bandsNarrowed > 0 {
            lines.append("- \(digest.bandsNarrowed) grade band\(digest.bandsNarrowed == 1 ? " narrowed" : "s narrowed") — those evaluations are firming up.")
        }
        if let headline = digest.headline {
            let direction = digest.headlineIsRise ? "up" : "down"
            lines.append("- Headline: \(headline.position) \(headline.name) moved \(direction) from \(headline.from) to \(headline.to).")
        }
        lines.append("")
        lines.append("Full write-ups are on the board.")
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: subject,
            body: lines.joined(separator: "\n"),
            date: "Week \(digest.week), Season \(season)",
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// One digest for the whole combine media sheet: who rose, who fell, who
    /// came out of nowhere.
    static func combineMediaDigestMessage(
        mentions: [ScoutingEngine.CombineMediaMention],
        dateString: String
    ) -> InboxMessage? {
        guard !mentions.isEmpty else { return nil }

        let risers = mentions.filter { $0.category == "Stock Riser" }
        let fallers = mentions.filter { $0.category == "Stock Faller" }
        let standouts = mentions.filter { $0.category == "Standout" }
        let surprises = mentions.filter { $0.category == "Surprise" }

        func block(_ title: String, _ rows: [ScoutingEngine.CombineMediaMention]) -> String? {
            guard !rows.isEmpty else { return nil }
            let names = rows.prefix(5).map { "- \($0.position) \($0.prospectName)" }
            return ([title] + names).joined(separator: "\n")
        }

        var sections: [String] = [
            "Coach,",
            "",
            "The combine sheet is closed. Here is what the week did to our board:"
        ]
        if let b = block("Stock up:", risers)                  { sections.append(""); sections.append(b) }
        if let b = block("Came out of nowhere:", surprises)    { sections.append(""); sections.append(b) }
        if let b = block("Stock down:", fallers)               { sections.append(""); sections.append(b) }
        if let b = block("Athletic standouts:", standouts)     { sections.append(""); sections.append(b) }
        sections.append("")
        sections.append("Testing is one input. The men on the 'stock down' list are where the value is if the tape still says what it said in November.")
        sections.append("")
        sections.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Combine board movement: \(risers.count) up, \(fallers.count) down",
            body: sections.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Combine Results", destination: .scouting),
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// The Showcase week report.
    static func seniorBowlDigestMessage(
        result: ScoutingEngine.SeniorBowlResult,
        dateString: String
    ) -> InboxMessage? {
        guard result.reportsFiled > 0 else { return nil }

        var lines: [String] = [
            "Coach,",
            "",
            "Showcase week is done. \(result.invitees) seniors were invited and we have written evaluations on \(result.reportsFiled) of them — the practice winners and the men who got exposed. The middle of that field did not tell us anything new.",
            ""
        ]
        let risers = result.notes.filter { $0.isRiser }
        let fallers = result.notes.filter { !$0.isRiser }
        if !risers.isEmpty {
            lines.append("Helped himself:")
            lines.append(contentsOf: risers.map { "- \($0.position) \($0.name) (\($0.college))" })
            lines.append("")
        }
        if !fallers.isEmpty {
            lines.append("Rough week:")
            lines.append(contentsOf: fallers.map { "- \($0.position) \($0.name) (\($0.college))" })
            lines.append("")
        }
        lines.append("These are practice grades against real competition, not workout numbers. They travel better than a forty time.")
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "The Showcase: \(result.reportsFiled) evaluations filed",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// The spring medical sheet — who got hurt between the combine and the draft.
    static func preDraftAttritionMessage(
        setbacks: [ScoutingEngine.PreDraftSetback],
        dateString: String
    ) -> InboxMessage? {
        guard !setbacks.isEmpty else { return nil }

        var lines: [String] = [
            "Coach,",
            "",
            "Medical update from the pro-day circuit. \(setbacks.count) prospect\(setbacks.count == 1 ? " has" : "s have") gone down since the combine:",
            ""
        ]
        for setback in setbacks.prefix(8) {
            var row = "- \(setback.position) \(setback.name) (\(setback.college)): \(setback.injury), ~\(setback.weeksOut) weeks"
            if let from = setback.projectionFrom, let to = setback.projectionTo, to > from {
                row += " — round \(from) to round \(to)"
            }
            lines.append(row)
        }
        lines.append("")
        lines.append("Every one of these is flagged on his file now. A club that trusts its medical staff can find a bargain in here; a club that guesses gets a redshirt rookie year.")
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Pre-draft medical: \(setbacks.count) prospect\(setbacks.count == 1 ? "" : "s") hurt",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// The pro-day circuit report: who finally tested, and what it changed.
    static func proDayCircuitMessage(
        result: ScoutingEngine.ProDayCircuitResult,
        moves: [ScoutingEngine.ProjectionMove],
        dateString: String
    ) -> InboxMessage? {
        guard result.tested > 0 else { return nil }

        var lines: [String] = [
            "Coach,",
            "",
            "The campus circuit is done. \(result.tested) men who had no number on them — combine no-shows and the whole uninvited half of the class — have now worked out at their own schools, and we have the results off the wire.",
            ""
        ]

        let risers = moves.filter(\.isRise).sorted { $0.rounds > $1.rounds }
        let fallers = moves.filter { !$0.isRise }.sorted { $0.rounds > $1.rounds }
        if !risers.isEmpty {
            lines.append("Helped himself:")
            lines.append(contentsOf: risers.prefix(5).map {
                "- \($0.position) \($0.name) (\($0.college)): round \($0.from) to round \($0.to)"
            })
            lines.append("")
        }
        if !fallers.isEmpty {
            lines.append("Did not:")
            lines.append(contentsOf: fallers.prefix(5).map {
                "- \($0.position) \($0.name) (\($0.college)): round \($0.from) to round \($0.to)"
            })
            lines.append("")
        }

        lines.append("Remember what these numbers are: hand-timed, on his own turf, in front of people who want him to look good. We discount them until one of ours holds the watch.")
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Pro-day circuit: \(result.tested) late testers on the board",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// The club's OWN pro-day circuit, filed by the men who went (#189).
    ///
    /// ``proDayCircuitMessage`` above is the other half of the same week and a
    /// different document: the league's campus circuit, read off the wire, for
    /// men nobody in this building watched. This one exists because the trip
    /// the user actually paid for produced no mail at all — the only record was
    /// a panel inside `ProDayTourView` that died with the view. The stage's
    /// whole currency is attention, and spending it left no trace in the one
    /// place the game keeps its history.
    ///
    /// Returns `nil` for a circuit that saw nobody, which includes the explicit
    /// skip. A letter announcing that the department stayed home is the no-op
    /// with a receipt this screen has already had to delete once.
    static func proDayTourDigestMessage(
        schools: [String],
        prospectsEvaluated: Int,
        findings: [String],
        dateString: String
    ) -> InboxMessage? {
        guard !schools.isEmpty, prospectsEvaluated > 0 else { return nil }

        let schoolCount = schools.count
        let schoolWord = schoolCount == 1 ? "school" : "schools"
        let manWord = prospectsEvaluated == 1 ? "man" : "men"

        var lines: [String] = [
            "Coach,",
            "",
            "The department is back. \(prospectsEvaluated) \(manWord) worked out in front of our own people at \(schoolCount) \(schoolWord): \(schools.joined(separator: ", ")).",
            "",
            "Every one of them is filed — our watch, our eyes, our report. That is the difference between these numbers and the ones the wire prints."
        ]

        if !findings.isEmpty {
            lines.append("")
            lines.append("Worth your time:")
            lines.append(contentsOf: findings.map { "- \($0)" })
        }

        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Pro day circuit complete \u{2014} \(prospectsEvaluated) \(manWord) seen at \(schoolCount) \(schoolWord)",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    // MARK: - The two mock-draft moments (#103 §5.7)

    /// The personnel director's read on a mock draft: here is where the league
    /// has our board.
    ///
    /// The feed item (`NewsGenerator.mockDraftEvent`) is the public half of the
    /// same moment — the top five and the loudest disagreement. This is the
    /// private half, and it is written from the club's side of the table: what
    /// the consensus expects US to do at our own pick, and which of the men we
    /// have graded the league is high or low on. Nothing here is new
    /// information about a prospect; it is the same public mock, read for what
    /// it implies about the room we are drafting into.
    ///
    /// - Parameters:
    ///   - history: the snapshot. Any order; sorted by pick number here.
    ///   - label: "Mock 1.0" or "Final Mock".
    ///   - userBoardTop: the club's own board, best man first — the same array
    ///     the feed item receives (see `NewsGenerator.mockDraftEvent`).
    ///   - userTeamAbbreviation: the club whose picks get called out. `nil`
    ///     (no team) drops the "our pick" paragraph rather than the message.
    static func mockDraftMessage(
        history: [ScoutingEngine.MockDraftPick],
        label: String,
        userBoardTop: [CollegeProspect],
        userTeamAbbreviation: String?,
        dateString: String
    ) -> InboxMessage? {
        guard !history.isEmpty else { return nil }

        let ordered = history.sorted { $0.pickNumber < $1.pickNumber }
        let prospectByID = Dictionary(
            userBoardTop.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var mockRank: [UUID: Int] = [:]
        for (index, pick) in ordered.enumerated() where mockRank[pick.prospectID] == nil {
            mockRank[pick.prospectID] = index + 1
        }

        func describe(_ id: UUID) -> String? {
            guard let prospect = prospectByID[id] else { return nil }
            return "\(prospect.position.rawValue) \(prospect.fullName) (\(prospect.college))"
        }

        var lines: [String] = [
            "Coach,",
            "",
            "\(label) is on every wire in the league. Here is where it has our board.",
            ""
        ]

        // 1. What the consensus expects us to do with our own picks.
        if let abbr = userTeamAbbreviation {
            let ours = ordered.filter { $0.teamAbbreviation == abbr }.prefix(3)
            if !ours.isEmpty {
                lines.append("Us:")
                for pick in ours {
                    let who = describe(pick.prospectID) ?? "a name we have not graded"
                    lines.append("- Pick \(pick.pickNumber) (round \(pick.round)): \(who)")
                }
                lines.append("")
            }
        }

        // 2. The men we have graded that the league is highest and lowest on.
        var boardSlot = 0
        var leagueHigh: [(gap: Int, line: String)] = []
        var leagueLow: [(gap: Int, line: String)] = []
        for prospect in userBoardTop.prefix(40) {
            guard prospect.scoutedOverall != nil else { continue }
            boardSlot += 1
            guard let league = mockRank[prospect.id] else { continue }
            let gap = league - boardSlot
            guard abs(gap) >= 6 else { continue }
            let line = "- \(prospect.position.rawValue) \(prospect.fullName) (\(prospect.college)): our No. \(boardSlot), league No. \(league)"
            if gap < 0 {
                leagueHigh.append((gap: -gap, line: line))
            } else {
                leagueLow.append((gap: gap, line: line))
            }
        }
        if !leagueHigh.isEmpty {
            lines.append("They are higher on than we are:")
            lines.append(contentsOf: leagueHigh.sorted { $0.gap > $1.gap }.prefix(3).map(\.line))
            lines.append("")
        }
        if !leagueLow.isEmpty {
            lines.append("They are lower on than we are:")
            lines.append(contentsOf: leagueLow.sorted { $0.gap > $1.gap }.prefix(3).map(\.line))
            lines.append("")
        }
        if leagueHigh.isEmpty && leagueLow.isEmpty {
            lines.append("Our grades and the consensus are sitting on top of each other at the top of the board. That is either agreement or a room that has not looked hard enough yet.")
            lines.append("")
        }

        lines.append("A mock is not a draft. It is thirty-two rooms guessing about thirty-one others — useful for knowing who will be gone, useless for knowing who is good.")
        lines.append("")
        lines.append("Player Personnel")

        return InboxMessage(
            sender: .scout(name: "Director of Player Personnel"),
            subject: "\(label): where the league has our board",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .draftPrep,
            attachments: [
                MessageAttachment(title: "Open Mock Draft", destination: .mockDraft),
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    /// The character memo — names only, never the file itself.
    ///
    /// The body deliberately does NOT print the flag: what the file says is
    /// disclosed by `ProspectFog.flagDisclosure`, i.e. by having filed reports,
    /// taken a meeting or spent a Top-30 visit. Mailing the text here would hand
    /// the user for free the one piece of intel the whole disclosure ladder is
    /// built to charge for.
    static func characterFindingsMessage(
        findings: [ScoutingEngine.CharacterFinding],
        dateString: String
    ) -> InboxMessage? {
        guard !findings.isEmpty else { return nil }

        var lines: [String] = [
            "Coach,",
            "",
            "Character work. \(findings.count) name\(findings.count == 1 ? " has" : "s have") come up this week that we did not have anything on in the fall:",
            ""
        ]
        for finding in findings {
            let round = finding.projection.map { "round \($0)" } ?? "undrafted"
            lines.append("- \(finding.position) \(finding.name) (\(finding.college)) — \(round) projection")
        }
        lines.append("")
        lines.append("I am not putting what we heard in writing. Get two reports on him, put him in a room, or spend a visit, and the file opens.")
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Character notes: \(findings.count) name\(findings.count == 1 ? "" : "s") to re-check",
            body: lines.joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    // MARK: - Draft-cycle heartbeat (task #78, finding S9)

    /// A two-line note from the scouting department at every phase boundary of
    /// the draft cycle.
    ///
    /// The offseason calendar used to be silent between the loud events: the
    /// user advanced a phase, the screen changed, and nothing told him what his
    /// own building had been doing or where the board stood. This is not a
    /// mechanic — it is the department checking in with real counts off the
    /// live class, so the four months read as a season of work rather than as
    /// four buttons.
    ///
    /// Returns `nil` for a phase outside the cycle or an empty class, so the
    /// caller can skip the message entirely rather than mail an empty one.
    static func draftCycleHeartbeat(
        phase: SeasonPhase,
        prospects: [CollegeProspect],
        dateString: String
    ) -> InboxMessage? {
        guard !prospects.isEmpty else { return nil }

        let declared = prospects.filter(\.isDeclaringForDraft)
        guard !declared.isEmpty else { return nil }
        // Our OWN paper only. `applyPreScoutedData` stamps a "Previous Staff"
        // report on the top ~250 of every class at career creation, so the raw
        // `!scoutingReports.isEmpty` ledger let the department mail "249 of 312
        // carry one of our reports" in a save where the user had ordered zero
        // film study — while the Scouting Hub header and the dashboard's
        // "% scouted" (both on `ProspectFog.hasOwnReport`) said 0%. Same
        // predicate here, so the three counters cannot disagree.
        let reported = declared.filter({ ProspectFog.hasOwnReport($0) }).count
        let interviewed = declared.filter(\.interviewCompleted).count
        let flagged = declared.filter { !($0.medicalConcerns ?? []).isEmpty }.count

        let subject: String
        let body: String
        switch phase {
        case .coachingChanges:
            // The window has ALREADY closed by the time this note is mailed:
            // `WeekAdvancer` runs `generateDeclarations` earlier in the same
            // `.coachingChanges` block, and that pass leaves every underclassman
            // `.declared` or `.withdrawn`. The old copy counted `.undecided` and
            // therefore shipped the sentence "0 underclassmen are still
            // deciding" in every save, every season. Report the outcome instead.
            let withdrew = prospects.filter { $0.declarationStatus == .withdrawn }.count
            let earlyEntrants = declared.filter(\.isUnderclassman).count
            subject = "Declaration window closed: \(declared.count) in the class"
            body = "The January deadline has passed. \(declared.count) players are in this draft, \(earlyEntrants) of them underclassmen who gave up eligibility to be here. \(withdrew) went back to school, and the men behind them at those positions just moved up our board. We have written reports on \(reported) so far."
        case .combine:
            subject = "Combine wrap: board settled, \(flagged) medical files open"
            body = "Indianapolis is closed. The board has settled after the testing: \(reported) of the \(declared.count) declared players carry one of our reports and \(interviewed) have been in a room with us. \(flagged) men are carrying a medical note we would want a second look at before the draft."
        case .freeAgency:
            subject = "Post-market board: 32 needs boards rebuilt"
            body = "The market has closed and every club in the league just changed what it needs. We have re-run the board against the new depth charts — the men who moved did so because somebody's roster moved, not because their tape did."
        case .proDays:
            subject = "Pro-day circuit: \(reported) of \(declared.count) covered"
            body = "The campus workouts are running. We have filed on \(reported) of the \(declared.count) declared players and interviewed \(interviewed). Anybody still uncovered is a man we will be drafting off somebody else's opinion."
        case .draft:
            subject = "Draft eve: \(reported) reports, \(interviewed) interviews on file"
            body = "Final board is locked. \(reported) of the \(declared.count) declared players carry at least one of our reports, \(interviewed) have been interviewed, and \(flagged) are flagged medically. Everything after this is the clock."
        default:
            return nil
        }

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: subject,
            body: ["Coach,", "", body, "", "Scouting Department"].joined(separator: "\n"),
            date: dateString,
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "Open Big Board", destination: .bigBoard)
            ]
        )
    }

    // MARK: - Retirement Realism (task #84)

    /// The letter a coach gets when one of HIS men walks away in his prime.
    ///
    /// Deliberately not the league-office roundup: this one is the player's own
    /// voice, because the shock retirement is the moment where the roster stops
    /// being a spreadsheet. The cap and roster consequences flow through the
    /// ordinary retirement path — nothing here moves a number.
    static func shockRetirementMessage(
        playerName: String,
        positionRaw: String,
        age: Int,
        seasonsPlayed: Int,
        careerWeeksOut: Int,
        dateString: String
    ) -> InboxMessage {
        InboxMessage(
            sender: .playerAgent(name: "\(playerName)'s agent"),
            subject: "\(playerName) is retiring — effective immediately",
            body: """
            Coach,

            I need you to hear this from me before it hits the wire. \(playerName) is retiring. Today. He is \(age) years old and he is done.

            You know the file as well as I do: \(seasonsPlayed) seasons, and something close to \(careerWeeksOut) weeks of them spent in a rehab room instead of on a field. The last scan was the one that decided it. He can pass a physical. He cannot promise anybody he will still be himself in December, and he will not take a cheque to find out.

            He asked me to tell you he never once thought about the money in this building and he is not starting now. It was not you, it was not the plan, and it is not a bluff for a new number.

            His roster spot and his cap number are yours again. I am sorry it is like this.

            — for \(playerName), \(positionRaw)
            """,
            date: dateString,
            category: .playerIssue,
            actionDestination: .roster
        )
    }

    /// The walk-off: an all-time great leaves while still an all-time great.
    static func retiresOnTopMessage(
        playerName: String,
        positionRaw: String,
        age: Int,
        overall: Int,
        rings: Int,
        resume: String?,
        dateString: String
    ) -> InboxMessage {
        let ringLine: String
        switch rings {
        case 0:  ringLine = ""
        case 1:  ringLine = " He goes out with a ring."
        default: ringLine = " He goes out with \(rings) rings."
        }
        let production = resume.map { "\n\nThe career line: \($0)." } ?? ""
        return InboxMessage(
            sender: .leagueOffice,
            subject: "\(playerName) retires while still the best in the league",
            body: """
            \(playerName) (\(positionRaw), age \(age)) has filed his retirement papers rated \(overall) overall. There is no injury behind it, no decline and no dispute — he decided that finishing at the top was worth more to him than two more seasons of being slightly less than this.\(ringLine)\(production)

            The league office does not often say this about a transaction: it is the right way to leave, and it is very rare.

            League Office
            """,
            date: dateString,
            category: .leagueNotice,
            actionDestination: .news
        )
    }

    /// The return. Sent league-wide, because a legend un-retiring changes the
    /// contender math for everybody — including the clubs he did not pick.
    static func comebackMessage(
        playerName: String,
        positionRaw: String,
        age: Int,
        teamName: String,
        seasonsAway: Int,
        isDivisionRival: Bool,
        dateString: String
    ) -> InboxMessage {
        let away = seasonsAway == 1 ? "one season" : "\(seasonsAway) seasons"
        let closer = isDivisionRival
            ? "He landed in our division. We see him twice, and the second time will be in December."
            : "He is somebody else's problem for now. He will not stay that way if either of us makes a run."
        return InboxMessage(
            sender: .media(outlet: "League Wire"),
            subject: "\(playerName) is coming out of retirement",
            body: """
            \(playerName) — \(positionRaw), \(age) years old, \(away) out of football — has signed a one-year deal with the \(teamName).

            He is not being paid like a star and nobody is pretending he is the player he was. He is there for one reason and he said it on the record: he wants the ring.

            \(closer)

            League Wire
            """,
            date: dateString,
            category: .leagueNotice,
            actionDestination: .news
        )
    }

    // MARK: - Helpers

    /// Creates a human-readable date string for the given phase.
    private static func dateLabel(for phase: SeasonPhase, career: Career) -> String {
        dateLabel(week: career.currentWeek, season: career.currentSeason, phase: phase)
    }

    /// Calendar-free variant for callers that have a week/season pair but no
    /// live `Career` — e.g. a `TradeRecord` row being announced after the fact.
    static func dateLabel(week: Int, season: Int, phase: SeasonPhase) -> String {
        switch phase {
        case .regularSeason:
            return "Week \(week), Season \(season)"
        case .playoffs:
            let roundName: String
            switch week {
            case 19: roundName = "Wild Card"
            case 20: roundName = "Divisional Round"
            case 21: roundName = "Conference Championship"
            default: roundName = "Playoffs"
            }
            return "\(roundName), Season \(season)"
        case .tradeDeadline:
            return "Week \(week), Season \(season)"
        default:
            let phaseName: String
            switch phase {
            case .superBowl:        phaseName = "The Championship"
            case .proBowl:          phaseName = "All-Star Game"
            case .coachingChanges:  phaseName = "Coaching Changes"
            case .combine:          phaseName = "The Combine"
            case .freeAgency:       phaseName = "Free Agency"
            case .proDays:          phaseName = "Pro Days & Workouts"
            case .reviewRoster:     phaseName = "Review Roster"
            case .draft:            phaseName = "The Draft"
            case .otas:             phaseName = "OTAs"
            case .trainingCamp:     phaseName = "Training Camp"
            case .preseason:        phaseName = "Preseason"
            case .rosterCuts:       phaseName = "Roster Cuts"
            default:                phaseName = "Offseason"
            }
            return "Offseason - \(phaseName), \(season)"
        }
    }

    private static func formatCap(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}
