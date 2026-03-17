import Foundation

/// Pre-written event templates for each EventType with placeholder substitution and response options.
enum EventTemplates {

    // MARK: - Template Data

    private struct Template {
        let headline: String
        let description: String
        let options: [EventOption]
    }

    // MARK: - Public Builder

    /// Constructs a `GameEvent` by selecting a random template for the given type
    /// and substituting placeholders.
    static func buildEvent(
        type: EventType,
        teamID: UUID,
        teamName: String,
        playerID: UUID?,
        playerName: String?,
        coachID: UUID?,
        coachName: String?,
        week: Int,
        season: Int
    ) -> GameEvent {
        let templates = templatesFor(type: type)
        let template = templates.randomElement() ?? templates[0]

        let headline = substitute(template.headline, playerName: playerName, teamName: teamName, coachName: coachName)
        let description = substitute(template.description, playerName: playerName, teamName: teamName, coachName: coachName)

        return GameEvent(
            type: type,
            headline: headline,
            description: description,
            playerID: playerID,
            coachID: coachID,
            teamID: teamID,
            options: template.options,
            week: week,
            season: season
        )
    }

    // MARK: - Placeholder Substitution

    private static func substitute(
        _ text: String,
        playerName: String?,
        teamName: String,
        coachName: String?
    ) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{playerName}", with: playerName ?? "A player")
        result = result.replacingOccurrences(of: "{teamName}", with: teamName)
        result = result.replacingOccurrences(of: "{coachName}", with: coachName ?? "The coach")
        return result
    }

    // MARK: - Templates By Type

    // swiftlint:disable function_body_length
    private static func templatesFor(type: EventType) -> [Template] {
        switch type {

        // ---------------------------------------------------------------
        // MARK: Holdout
        // ---------------------------------------------------------------
        case .holdout:
            return [
                Template(
                    headline: "{playerName} refuses to report to training camp",
                    description: "{playerName} has informed the {teamName} that he will not participate in team activities until his contract situation is resolved. His agent says the current deal no longer reflects his value to the team.",
                    options: [
                        EventOption(label: "Restructure contract", description: "Give him a raise and restructure the deal to keep him happy.", moraleEffect: 15, lockerRoomEffect: 5, ownerEffect: -5, mediaEffect: 2),
                        EventOption(label: "Stand firm", description: "Refuse to renegotiate. A deal is a deal.", moraleEffect: -15, lockerRoomEffect: -5, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Explore trade options", description: "Quietly shop the player to see what you can get in return.", moraleEffect: -10, lockerRoomEffect: -3, ownerEffect: 0, mediaEffect: -3),
                        EventOption(label: "Wait it out", description: "Let the situation cool down without making a move.", moraleEffect: -5, lockerRoomEffect: -2, ownerEffect: 0, mediaEffect: -1)
                    ]
                ),
                Template(
                    headline: "{playerName} skips mandatory minicamp amid contract dispute",
                    description: "The {teamName} star is willing to absorb daily fines rather than report without a new deal. Teammates have been reaching out privately to urge his return.",
                    options: [
                        EventOption(label: "Fine the player", description: "Enforce the fines and make a public statement about team rules.", moraleEffect: -12, lockerRoomEffect: -4, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Open negotiations", description: "Bring the agent in for good-faith talks.", moraleEffect: 10, lockerRoomEffect: 3, ownerEffect: -3, mediaEffect: 3),
                        EventOption(label: "Have a captain mediate", description: "Ask a team leader to talk some sense into him.", moraleEffect: 5, lockerRoomEffect: 5, ownerEffect: 0, mediaEffect: 1)
                    ]
                ),
                Template(
                    headline: "{playerName} posts cryptic social media message hinting at holdout",
                    description: "{playerName} shared an hourglass emoji and the words 'Time's up' on social media, fueling speculation that he is prepared to sit out unless the {teamName} meet his contract demands.",
                    options: [
                        EventOption(label: "Address it publicly", description: "Hold a press conference reaffirming your commitment to the player.", moraleEffect: 5, lockerRoomEffect: 2, ownerEffect: -2, mediaEffect: 3),
                        EventOption(label: "Ignore the noise", description: "Don't feed the media frenzy. Business as usual.", moraleEffect: -3, lockerRoomEffect: 0, ownerEffect: 2, mediaEffect: -1),
                        EventOption(label: "Call the player directly", description: "Have a private one-on-one conversation.", moraleEffect: 8, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 0)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Suspension
        // ---------------------------------------------------------------
        case .suspension:
            return [
                Template(
                    headline: "{playerName} suspended for violating league policy",
                    description: "The league has handed down a multi-game suspension to {playerName} of the {teamName} for violating the league's personal conduct policy. The team must now prepare without a key contributor.",
                    options: [
                        EventOption(label: "Support the player publicly", description: "Stand behind your player and express confidence in his character.", moraleEffect: 10, lockerRoomEffect: 5, ownerEffect: -5, mediaEffect: -3),
                        EventOption(label: "Condemn the behavior", description: "Issue a strong statement distancing the organization from the actions.", moraleEffect: -10, lockerRoomEffect: -3, ownerEffect: 5, mediaEffect: 3),
                        EventOption(label: "No comment", description: "Decline to comment and let the process play out.", moraleEffect: -2, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: -1)
                    ]
                ),
                Template(
                    headline: "{playerName} facing league suspension for substance abuse",
                    description: "{playerName} has entered Stage Two of the league's substance abuse program and faces a four-game ban. The {teamName} are evaluating their options.",
                    options: [
                        EventOption(label: "Offer support resources", description: "Connect the player with team counselors and support staff.", moraleEffect: 8, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Explore release", description: "Evaluate whether to cut ties entirely.", moraleEffect: -15, lockerRoomEffect: -5, ownerEffect: 3, mediaEffect: -2),
                        EventOption(label: "Wait for appeal", description: "Let the appeals process run its course.", moraleEffect: 0, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Arrest
        // ---------------------------------------------------------------
        case .arrest:
            return [
                Template(
                    headline: "{playerName} arrested in offseason incident",
                    description: "{playerName} of the {teamName} was arrested early this morning. Details are still emerging but the team has been made aware of the situation.",
                    options: [
                        EventOption(label: "Suspend indefinitely", description: "Place the player on the exempt list pending investigation.", moraleEffect: -15, lockerRoomEffect: -5, ownerEffect: 5, mediaEffect: 2),
                        EventOption(label: "Wait for facts", description: "Withhold judgment until the legal process plays out.", moraleEffect: -3, lockerRoomEffect: -2, ownerEffect: -3, mediaEffect: -2),
                        EventOption(label: "Release the player", description: "Cut ties immediately to protect the brand.", moraleEffect: -20, lockerRoomEffect: -8, ownerEffect: 8, mediaEffect: 3)
                    ]
                ),
                Template(
                    headline: "{playerName} involved in late-night altercation",
                    description: "Police were called to a downtown establishment after {playerName} was involved in an altercation. No charges have been filed yet, but the {teamName} are monitoring the situation.",
                    options: [
                        EventOption(label: "Impose team discipline", description: "Fine the player internally and restrict off-field activities.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 3, mediaEffect: 1),
                        EventOption(label: "Talk to the player privately", description: "Have a frank discussion behind closed doors.", moraleEffect: 2, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0),
                        EventOption(label: "Mandatory community service", description: "Require the player to participate in community outreach.", moraleEffect: -3, lockerRoomEffect: 2, ownerEffect: 3, mediaEffect: 4)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Social Media Incident
        // ---------------------------------------------------------------
        case .socialMediaIncident:
            return [
                Template(
                    headline: "{playerName} causes stir with controversial social media post",
                    description: "{playerName} posted inflammatory content on social media that has gone viral. The {teamName} are dealing with a public relations headache as the post draws national attention.",
                    options: [
                        EventOption(label: "Force a public apology", description: "Require the player to issue a formal apology.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 3, mediaEffect: 3),
                        EventOption(label: "Restrict social media use", description: "Implement a team social media policy.", moraleEffect: -5, lockerRoomEffect: -3, ownerEffect: 2, mediaEffect: 1),
                        EventOption(label: "Downplay the situation", description: "Treat it as a non-issue and move on.", moraleEffect: 3, lockerRoomEffect: 0, ownerEffect: -3, mediaEffect: -3)
                    ]
                ),
                Template(
                    headline: "{playerName} takes shot at coaching staff on social media",
                    description: "In a since-deleted post, {playerName} appeared to criticize the {teamName} coaching staff's play-calling. Screenshots have already spread across the internet.",
                    options: [
                        EventOption(label: "Demand a team meeting", description: "Address it directly in front of the whole team.", moraleEffect: -5, lockerRoomEffect: 5, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Bench the player", description: "Sit him for the next game as a message.", moraleEffect: -15, lockerRoomEffect: -3, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Private conversation", description: "Handle it behind closed doors without making a scene.", moraleEffect: 3, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "{playerName} tweets support for teammate amid controversy",
                    description: "{playerName} publicly backed a {teamName} teammate who has been under media scrutiny, showing solidarity but also drawing more attention to the situation.",
                    options: [
                        EventOption(label: "Praise the loyalty", description: "Commend the player for supporting a teammate.", moraleEffect: 5, lockerRoomEffect: 5, ownerEffect: -2, mediaEffect: 1),
                        EventOption(label: "Ask for discretion", description: "Privately ask players to stay off social media during the situation.", moraleEffect: -2, lockerRoomEffect: 0, ownerEffect: 2, mediaEffect: 1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Retirement Speculation
        // ---------------------------------------------------------------
        case .retirementSpeculation:
            return [
                Template(
                    headline: "{playerName} hints this could be his final season",
                    description: "In a candid interview, {playerName} of the {teamName} said he's 'taking it one year at a time' and hasn't committed to playing beyond this season.",
                    options: [
                        EventOption(label: "Give him a farewell tour", description: "Celebrate the veteran and let him enjoy the ride.", moraleEffect: 10, lockerRoomEffect: 5, ownerEffect: 2, mediaEffect: 5),
                        EventOption(label: "Start planning his replacement", description: "Begin looking at draft picks and free agents for the position.", moraleEffect: -5, lockerRoomEffect: -3, ownerEffect: 3, mediaEffect: -1),
                        EventOption(label: "Convince him to stay", description: "Express how much he means to the franchise.", moraleEffect: 8, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 2)
                    ]
                ),
                Template(
                    headline: "Report: {playerName} considering retirement",
                    description: "Sources close to {playerName} say the {teamName} veteran is seriously weighing retirement after dealing with nagging injuries and diminished production.",
                    options: [
                        EventOption(label: "Offer a reduced role", description: "Suggest a mentoring role with less playing time.", moraleEffect: 3, lockerRoomEffect: 5, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Respect his decision", description: "Let him make the call on his own timeline.", moraleEffect: 5, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Podcast Controversy
        // ---------------------------------------------------------------
        case .podcastControversy:
            return [
                Template(
                    headline: "{playerName} makes waves on popular podcast appearance",
                    description: "{playerName} appeared on a nationally syndicated podcast and made comments criticizing the {teamName} front office. The episode has already generated thousands of clicks.",
                    options: [
                        EventOption(label: "Address the comments publicly", description: "Respond calmly in a press conference.", moraleEffect: -3, lockerRoomEffect: 2, ownerEffect: -3, mediaEffect: 2),
                        EventOption(label: "Fine the player", description: "Impose an internal fine for detrimental conduct.", moraleEffect: -10, lockerRoomEffect: -5, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Laugh it off", description: "Make light of the comments and move on.", moraleEffect: 5, lockerRoomEffect: 3, ownerEffect: -2, mediaEffect: 1)
                    ]
                ),
                Template(
                    headline: "{playerName} reveals locker room secrets on podcast",
                    description: "During a freewheeling podcast interview, {playerName} shared behind-the-scenes details about the {teamName} locker room, catching teammates and coaches off guard.",
                    options: [
                        EventOption(label: "Hold a team meeting", description: "Clear the air with the full roster.", moraleEffect: -2, lockerRoomEffect: 5, ownerEffect: 0, mediaEffect: 1),
                        EventOption(label: "Ban media appearances", description: "Implement a temporary media blackout for the team.", moraleEffect: -8, lockerRoomEffect: -3, ownerEffect: 3, mediaEffect: -4),
                        EventOption(label: "Ignore it", description: "Don't give the story more oxygen than it deserves.", moraleEffect: 0, lockerRoomEffect: -2, ownerEffect: -1, mediaEffect: -2)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Man of the Year
        // ---------------------------------------------------------------
        case .manOfTheYear:
            return [
                Template(
                    headline: "{playerName} nominated for Man of the Year award",
                    description: "{playerName} of the {teamName} has been nominated for the league's prestigious Man of the Year award, recognizing his outstanding community service and philanthropic efforts.",
                    options: [
                        EventOption(label: "Celebrate publicly", description: "Hold a press conference to honor the nomination.", moraleEffect: 10, lockerRoomEffect: 5, ownerEffect: 5, mediaEffect: 5),
                        EventOption(label: "Let the work speak for itself", description: "Quietly acknowledge the nomination without making a fuss.", moraleEffect: 5, lockerRoomEffect: 3, ownerEffect: 2, mediaEffect: 2)
                    ]
                ),
                Template(
                    headline: "{playerName} opens youth center in hometown",
                    description: "{playerName} invested in building a state-of-the-art youth center in his hometown, bringing positive attention to the {teamName} organization.",
                    options: [
                        EventOption(label: "Match the donation", description: "Have the franchise contribute matching funds.", moraleEffect: 8, lockerRoomEffect: 5, ownerEffect: 5, mediaEffect: 5),
                        EventOption(label: "Acknowledge the gesture", description: "Release a statement praising the player.", moraleEffect: 5, lockerRoomEffect: 3, ownerEffect: 2, mediaEffect: 3)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Voluntary Workouts
        // ---------------------------------------------------------------
        case .voluntaryWorkouts:
            return [
                Template(
                    headline: "{teamName} report strong voluntary workout attendance",
                    description: "Nearly the entire {teamName} roster has shown up for voluntary offseason workouts, a sign of strong team chemistry and buy-in from the locker room.",
                    options: [
                        EventOption(label: "Praise the commitment", description: "Commend the players for their dedication in your next press conference.", moraleEffect: 3, lockerRoomEffect: 5, ownerEffect: 3, mediaEffect: 3),
                        EventOption(label: "Stay cautious", description: "Appreciate it privately but keep expectations measured publicly.", moraleEffect: 1, lockerRoomEffect: 2, ownerEffect: 1, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "{teamName} veterans organize player-led workouts",
                    description: "Several veteran leaders on the {teamName} have organized informal workouts at a local facility, bringing together starters and newcomers alike.",
                    options: [
                        EventOption(label: "Join a session", description: "Show up to observe and show you appreciate the effort.", moraleEffect: 5, lockerRoomEffect: 5, ownerEffect: 2, mediaEffect: 2),
                        EventOption(label: "Give them space", description: "Let the players bond on their own terms.", moraleEffect: 2, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 0)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Rookie Impresses
        // ---------------------------------------------------------------
        case .rookieImpresses:
            return [
                Template(
                    headline: "{playerName} turning heads in first NFL practices",
                    description: "Rookie {playerName} has been the talk of {teamName} camp. Coaches and teammates alike have praised the young player's work ethic and natural ability.",
                    options: [
                        EventOption(label: "Increase his reps", description: "Give the rookie more first-team opportunities.", moraleEffect: 10, lockerRoomEffect: 2, ownerEffect: 3, mediaEffect: 3),
                        EventOption(label: "Keep expectations in check", description: "Maintain the current development plan without rushing him.", moraleEffect: 3, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 0),
                        EventOption(label: "Pair him with a mentor", description: "Assign a veteran to guide his development.", moraleEffect: 8, lockerRoomEffect: 5, ownerEffect: 2, mediaEffect: 2)
                    ]
                ),
                Template(
                    headline: "{playerName} makes highlight-reel play in practice",
                    description: "Social media is buzzing after a clip of {playerName} making an incredible play during {teamName} practice surfaced online. The rookie is generating serious hype.",
                    options: [
                        EventOption(label: "Hype him up", description: "Let the excitement build naturally.", moraleEffect: 8, lockerRoomEffect: 0, ownerEffect: 2, mediaEffect: 4),
                        EventOption(label: "Tamp down expectations", description: "Remind the media it's just practice.", moraleEffect: -2, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: -1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Coach Conflict
        // ---------------------------------------------------------------
        case .coachConflict:
            return [
                Template(
                    headline: "{coachName} involved in heated sideline argument",
                    description: "{coachName} was seen in an animated confrontation with a player on the {teamName} sideline during the game. Cameras captured the exchange, which is now circulating on social media.",
                    options: [
                        EventOption(label: "Back the coach", description: "Support the coaching staff's authority publicly.", moraleEffect: -5, lockerRoomEffect: -3, ownerEffect: 5, mediaEffect: 1),
                        EventOption(label: "Mediate", description: "Sit both parties down and work through it.", moraleEffect: 3, lockerRoomEffect: 5, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Discipline both", description: "Fine both parties for unprofessional conduct.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 3, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "Reports of tension between {coachName} and front office",
                    description: "Sources inside the {teamName} organization say there is growing friction between {coachName} and the front office over personnel decisions and roster construction.",
                    options: [
                        EventOption(label: "Meet privately", description: "Have a closed-door conversation to clear the air.", moraleEffect: 0, lockerRoomEffect: 3, ownerEffect: 3, mediaEffect: 1),
                        EventOption(label: "Assert authority", description: "Make it clear who has final say on roster decisions.", moraleEffect: 0, lockerRoomEffect: -2, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Compromise", description: "Find a middle ground that keeps both sides satisfied.", moraleEffect: 0, lockerRoomEffect: 5, ownerEffect: -2, mediaEffect: 2)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Coordinator Interview
        // ---------------------------------------------------------------
        case .coordinatorInterview:
            return [
                Template(
                    headline: "{coachName} receiving head coaching interview requests",
                    description: "Multiple teams have requested permission to interview {coachName} of the {teamName} for their vacant head coaching position. It's a testament to the staff's success.",
                    options: [
                        EventOption(label: "Grant permission gracefully", description: "Allow the interviews and wish them well.", moraleEffect: 0, lockerRoomEffect: 0, ownerEffect: 2, mediaEffect: 3),
                        EventOption(label: "Offer a promotion", description: "Try to retain them with a new title or responsibilities.", moraleEffect: 0, lockerRoomEffect: 3, ownerEffect: -2, mediaEffect: 2),
                        EventOption(label: "Block interviews (if allowed)", description: "Use any contractual leverage to prevent the interview.", moraleEffect: 0, lockerRoomEffect: -3, ownerEffect: 0, mediaEffect: -3)
                    ]
                ),
                Template(
                    headline: "{coachName} a finalist for head coaching job elsewhere",
                    description: "{coachName} has advanced to the final round of interviews for another team's head coaching vacancy. The {teamName} may need to prepare a contingency plan.",
                    options: [
                        EventOption(label: "Begin internal search", description: "Start identifying potential replacements just in case.", moraleEffect: 0, lockerRoomEffect: -2, ownerEffect: 3, mediaEffect: 0),
                        EventOption(label: "Make a retention offer", description: "Put together a competitive package to keep the coach.", moraleEffect: 0, lockerRoomEffect: 3, ownerEffect: -3, mediaEffect: 2)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Veteran Return
        // ---------------------------------------------------------------
        case .veteranReturn:
            return [
                Template(
                    headline: "{playerName} returns to practice, energizes {teamName} locker room",
                    description: "After weeks on the sideline, {playerName} rejoined {teamName} practice today. Teammates swarmed the veteran upon his arrival, a clear sign of his importance to the team.",
                    options: [
                        EventOption(label: "Ease him back in", description: "Put him on a limited snap count initially.", moraleEffect: 5, lockerRoomEffect: 5, ownerEffect: 2, mediaEffect: 2),
                        EventOption(label: "Start him immediately", description: "Throw him right back into the starting lineup.", moraleEffect: 8, lockerRoomEffect: 3, ownerEffect: 3, mediaEffect: 3)
                    ]
                ),
                Template(
                    headline: "{playerName} says he's 'better than ever' ahead of return",
                    description: "Speaking to reporters, {playerName} expressed supreme confidence in his condition and declared himself ready to contribute immediately for the {teamName}.",
                    options: [
                        EventOption(label: "Match his energy", description: "Express confidence in the player to the media.", moraleEffect: 8, lockerRoomEffect: 3, ownerEffect: 2, mediaEffect: 3),
                        EventOption(label: "Manage expectations", description: "Remind everyone that returning to form takes time.", moraleEffect: -2, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: -1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Injury Setback
        // ---------------------------------------------------------------
        case .injurySetback:
            return [
                Template(
                    headline: "{playerName} suffers setback in rehab, timeline pushed back",
                    description: "{playerName} experienced a setback during rehabilitation and the {teamName} have announced his return will be delayed by several additional weeks.",
                    options: [
                        EventOption(label: "Shut him down for the season", description: "Prioritize long-term health over this season.", moraleEffect: -10, lockerRoomEffect: -3, ownerEffect: -3, mediaEffect: -2),
                        EventOption(label: "Seek a second opinion", description: "Send him to a specialist for further evaluation.", moraleEffect: -2, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0),
                        EventOption(label: "Adjust the rehab plan", description: "Work with trainers to modify the recovery approach.", moraleEffect: 0, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "{playerName} re-aggravates injury during light workout",
                    description: "The {teamName} received bad news today as {playerName} re-aggravated his injury during what was supposed to be a routine light workout. His status is now week-to-week.",
                    options: [
                        EventOption(label: "Place on IR", description: "Move him to injured reserve to ensure a full recovery.", moraleEffect: -8, lockerRoomEffect: -3, ownerEffect: -2, mediaEffect: -1),
                        EventOption(label: "Day-to-day evaluation", description: "Take a cautious approach and evaluate daily.", moraleEffect: -3, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Ahead of Schedule
        // ---------------------------------------------------------------
        case .aheadOfSchedule:
            return [
                Template(
                    headline: "{playerName} ahead of schedule in injury recovery",
                    description: "Great news for the {teamName}: {playerName} is progressing faster than expected in his rehabilitation and could return weeks earlier than initially projected.",
                    options: [
                        EventOption(label: "Push for early return", description: "Accelerate the timeline to get him back on the field.", moraleEffect: 10, lockerRoomEffect: 5, ownerEffect: 3, mediaEffect: 3),
                        EventOption(label: "Stick to the original plan", description: "Don't rush it. Follow the medical staff's original timeline.", moraleEffect: 3, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "Doctors clear {playerName} for full contact ahead of schedule",
                    description: "{playerName} received full medical clearance today, weeks ahead of the projected timeline. The {teamName} now have a key piece back in the fold.",
                    options: [
                        EventOption(label: "Activate immediately", description: "Add him to the active roster for this week.", moraleEffect: 10, lockerRoomEffect: 5, ownerEffect: 3, mediaEffect: 4),
                        EventOption(label: "Ramp up gradually", description: "Bring him along slowly with limited snaps.", moraleEffect: 5, lockerRoomEffect: 3, ownerEffect: 1, mediaEffect: 1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Freak Injury
        // ---------------------------------------------------------------
        case .freakInjury:
            return [
                Template(
                    headline: "{playerName} suffers freak injury during routine drill",
                    description: "{playerName} went down during a non-contact portion of {teamName} practice with what appears to be a significant injury. The team is awaiting test results.",
                    options: [
                        EventOption(label: "Address the team", description: "Rally the locker room and remind them to stay focused.", moraleEffect: -5, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 1),
                        EventOption(label: "Explore replacements", description: "Immediately begin evaluating available options at the position.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 2, mediaEffect: 0),
                        EventOption(label: "Next man up mentality", description: "Publicly express confidence in the backup.", moraleEffect: -3, lockerRoomEffect: 5, ownerEffect: 1, mediaEffect: 2)
                    ]
                ),
                Template(
                    headline: "{playerName} injures hand in bizarre off-field accident",
                    description: "{playerName} reportedly suffered a hand injury in a non-football accident. The {teamName} are still gathering details on the severity and expected recovery time.",
                    options: [
                        EventOption(label: "Discipline the player", description: "Fine him for putting himself at risk off the field.", moraleEffect: -10, lockerRoomEffect: -3, ownerEffect: 3, mediaEffect: -1),
                        EventOption(label: "Focus on recovery", description: "Get him the best medical care and move forward.", moraleEffect: 0, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 0),
                        EventOption(label: "Keep it quiet", description: "Minimize the story and list him as questionable.", moraleEffect: 0, lockerRoomEffect: 0, ownerEffect: -2, mediaEffect: -2)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Contract Dispute
        // ---------------------------------------------------------------
        case .contractDispute:
            return [
                Template(
                    headline: "{playerName} publicly demands new contract from {teamName}",
                    description: "{playerName} told reporters that he believes he is significantly underpaid relative to his production and is seeking a new deal from the {teamName} immediately.",
                    options: [
                        EventOption(label: "Open negotiations", description: "Begin talks on an extension or restructure.", moraleEffect: 10, lockerRoomEffect: 2, ownerEffect: -5, mediaEffect: 2),
                        EventOption(label: "Refuse to negotiate mid-season", description: "Tell his agent to wait until the offseason.", moraleEffect: -10, lockerRoomEffect: -3, ownerEffect: 5, mediaEffect: -2),
                        EventOption(label: "Offer incentive bonuses", description: "Add performance escalators without changing the base deal.", moraleEffect: 5, lockerRoomEffect: 0, ownerEffect: 0, mediaEffect: 1)
                    ]
                ),
                Template(
                    headline: "{playerName}'s agent goes public with contract frustrations",
                    description: "The agent for {playerName} told multiple national reporters that negotiations with the {teamName} have been 'disrespectful' and that his client deserves better.",
                    options: [
                        EventOption(label: "Meet with the agent", description: "Schedule a face-to-face to smooth things over.", moraleEffect: 5, lockerRoomEffect: 0, ownerEffect: -2, mediaEffect: 1),
                        EventOption(label: "Issue a statement", description: "Release a statement reaffirming commitment to the player.", moraleEffect: 3, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Stand firm publicly", description: "Tell the media the team's position hasn't changed.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 5, mediaEffect: -2)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Trade Request
        // ---------------------------------------------------------------
        case .tradeRequest:
            return [
                Template(
                    headline: "{playerName} formally requests trade from {teamName}",
                    description: "{playerName} has submitted a formal trade request to the {teamName} front office. His agent confirmed the news and said the player is looking for a fresh start.",
                    options: [
                        EventOption(label: "Honor the request", description: "Begin fielding trade offers immediately.", moraleEffect: -5, lockerRoomEffect: -5, ownerEffect: 0, mediaEffect: -2),
                        EventOption(label: "Try to convince him to stay", description: "Have a heart-to-heart conversation about the team's direction.", moraleEffect: 5, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 1),
                        EventOption(label: "Deny the request", description: "Tell him he's under contract and will play for the team.", moraleEffect: -15, lockerRoomEffect: -5, ownerEffect: 5, mediaEffect: -3),
                        EventOption(label: "Set a high asking price", description: "Make it known you'll trade him, but only for significant return.", moraleEffect: -8, lockerRoomEffect: -2, ownerEffect: 3, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "{playerName} 'unhappy' with role on {teamName}, per sources",
                    description: "League sources indicate that {playerName} is frustrated with his usage in the {teamName} offense and has quietly expressed a desire to be traded to a team where he can be featured more prominently.",
                    options: [
                        EventOption(label: "Increase his role", description: "Adjust the game plan to feature him more.", moraleEffect: 12, lockerRoomEffect: -2, ownerEffect: 0, mediaEffect: 2),
                        EventOption(label: "Have a direct conversation", description: "Explain the team's vision and where he fits.", moraleEffect: 3, lockerRoomEffect: 2, ownerEffect: 0, mediaEffect: 0),
                        EventOption(label: "Shop him quietly", description: "Gauge the trade market without making it public.", moraleEffect: -5, lockerRoomEffect: -2, ownerEffect: 2, mediaEffect: -1)
                    ]
                )
            ]

        // ---------------------------------------------------------------
        // MARK: Team Chemistry
        // ---------------------------------------------------------------
        case .teamChemistry:
            return [
                Template(
                    headline: "{teamName} locker room chemistry at an all-time high",
                    description: "Players and coaches on the {teamName} say the team's bond this season is special. Multiple players have described it as the best locker room they've ever been a part of.",
                    options: [
                        EventOption(label: "Organize a team dinner", description: "Bring the whole team together for a bonding event.", moraleEffect: 5, lockerRoomEffect: 8, ownerEffect: 3, mediaEffect: 3),
                        EventOption(label: "Stay focused", description: "Appreciate the chemistry but keep the focus on winning.", moraleEffect: 2, lockerRoomEffect: 3, ownerEffect: 2, mediaEffect: 1)
                    ]
                ),
                Template(
                    headline: "{teamName} players rally around injured teammate",
                    description: "The {teamName} have dedicated their season to a teammate sidelined by injury. The rallying cry has united the locker room and given the team an emotional edge.",
                    options: [
                        EventOption(label: "Lean into the storyline", description: "Let the emotion fuel the team's drive.", moraleEffect: 5, lockerRoomEffect: 8, ownerEffect: 3, mediaEffect: 5),
                        EventOption(label: "Keep it in-house", description: "Appreciate the sentiment but don't let it become a distraction.", moraleEffect: 2, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 0)
                    ]
                ),
                Template(
                    headline: "{teamName} hold players-only meeting, emerge unified",
                    description: "After a difficult stretch, {teamName} players held a closed-door meeting without coaches. Players emerged saying the air has been cleared and the team is refocused.",
                    options: [
                        EventOption(label: "Trust the leaders", description: "Let the players police themselves and show faith in the culture.", moraleEffect: 5, lockerRoomEffect: 8, ownerEffect: 2, mediaEffect: 3),
                        EventOption(label: "Follow up individually", description: "Check in with key players to understand what was discussed.", moraleEffect: 2, lockerRoomEffect: 3, ownerEffect: 0, mediaEffect: 0)
                    ]
                )
            ]
        }
    }
    // swiftlint:enable function_body_length
}
