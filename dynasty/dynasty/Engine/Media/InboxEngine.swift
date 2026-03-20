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
            - NFL COMBINE: Evaluate draft prospects and athletic testing
            - FREE AGENCY: Sign free agents and manage your salary cap
            - NFL DRAFT: Select the next generation of talent
            - OTAs: Set your depth chart and install schemes
            - TRAINING CAMP: Evaluate roster battles and player development
            - PRESEASON: Exhibition games for final evaluations
            - ROSTER CUTS: Trim to 53 players

            Best of luck this season.

            NFL League Office
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
            sender: .media(outlet: "NFL Network"),
            subject: "Mock Draft: \(teamName) Projected to Select...",
            body: """
            In our latest mock draft, national analysts are projecting the \(teamName) to select a \(projectedPosition) in the first round.

            "This team has a clear need at \(projectedPosition), and with the talent available in this class, they'd be smart to address it early," said our lead draft analyst.

            Of course, mock drafts are just projections. The combine can shake things up, and teams often go in unexpected directions on draft day.

            NFL Network Draft Coverage
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

        // Agent reaching out
        let agentNames = ["Drew Rosenhaus", "Tom Condon", "Joel Segal", "Todd France", "Ben Dogra"]
        let agentName = agentNames.randomElement() ?? "Drew Rosenhaus"
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

            NFL League Office
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

            NFL League Office
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
                sender: .media(outlet: "ESPN"),
                subject: "Training Camp Preview: \(teamName)",
                body: """
                Our training camp preview series continues with a look at the \(teamName). Key storylines to watch:

                - How will the new additions integrate with the existing roster?
                - Which position battles will shape the 53-man roster?
                - Can the coaching staff get the most out of this talent?

                We'll be tracking developments throughout camp and providing daily updates.

                ESPN NFL Coverage
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
                sender: .media(outlet: "Fox Sports"),
                subject: "Preseason Predictions: Where Does \(teamName) Rank?",
                body: """
                As preseason games get underway, our analysts have released their initial predictions for the upcoming season.

                The \(teamName) are generating buzz, but preseason games are about evaluation, not results. Smart coaches use this time to make final roster decisions and fine-tune their schemes.

                Fox Sports NFL Coverage
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

                NFL League Office
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

                NFL League Office
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

    // MARK: - Super Bowl

    private static func superBowlMessages(
        ownerName: String, dateString: String
    ) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .leagueOffice,
                subject: "Super Bowl Results",
                body: """
                The Super Bowl has been played. Review the results and league awards as we transition into the offseason.

                Congratulations to all teams on a competitive season.

                NFL League Office
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

    // MARK: - Pro Bowl

    private static func proBowlMessages(dateString: String) -> [InboxMessage] {
        [
            InboxMessage(
                sender: .leagueOffice,
                subject: "Pro Bowl Selections Announced",
                body: """
                The Pro Bowl rosters have been announced. Check your roster to see if any of your players earned this recognition.

                Pro Bowl selections are a testament to individual excellence and reflect well on the coaching staff.

                NFL League Office
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
            sender: .media(outlet: "ESPN"),
            subject: "Playoff Spotlight on \(teamName)",
            body: """
            The \(teamName) are in the playoffs, and all eyes are on the coaching staff. How will they handle the pressure of win-or-go-home football?

            Our analysts will be covering every angle of this matchup.

            ESPN NFL Playoffs
            """,
            date: dateString,
            category: .mediaRequest
        ))

        return messages
    }

    // MARK: - Trade Deadline

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

    // MARK: - Helpers

    /// Creates a human-readable date string for the given phase.
    private static func dateLabel(for phase: SeasonPhase, career: Career) -> String {
        switch phase {
        case .regularSeason:
            return "Week \(career.currentWeek), Season \(career.currentSeason)"
        case .playoffs:
            let roundName: String
            switch career.currentWeek {
            case 19: roundName = "Wild Card"
            case 20: roundName = "Divisional Round"
            case 21: roundName = "Conference Championship"
            default: roundName = "Playoffs"
            }
            return "\(roundName), Season \(career.currentSeason)"
        case .tradeDeadline:
            return "Week \(career.currentWeek), Season \(career.currentSeason)"
        default:
            let phaseName: String
            switch phase {
            case .superBowl:        phaseName = "Super Bowl"
            case .proBowl:          phaseName = "Pro Bowl"
            case .coachingChanges:  phaseName = "Coaching Changes"
            case .combine:          phaseName = "NFL Combine"
            case .freeAgency:       phaseName = "Free Agency"
            case .proDays:          phaseName = "Pro Days & Workouts"
            case .reviewRoster:     phaseName = "Review Roster"
            case .draft:            phaseName = "NFL Draft"
            case .otas:             phaseName = "OTAs"
            case .trainingCamp:     phaseName = "Training Camp"
            case .preseason:        phaseName = "Preseason"
            case .rosterCuts:       phaseName = "Roster Cuts"
            default:                phaseName = "Offseason"
            }
            return "Offseason - \(phaseName), \(career.currentSeason)"
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
