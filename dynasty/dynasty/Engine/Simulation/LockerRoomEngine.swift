import Foundation

// MARK: - Locker Room State

struct LockerRoomState: Codable {
    /// Overall team chemistry rating from 0 to 100. Derived from
    /// `leadershipScore - toxicityScore` **per player** — see
    /// `LockerRoomEngine.chemistryRating(net:headcount:)`.
    var teamChemistry: Int
    /// Raw SUM of positive leader contributions across the roster. Scales with
    /// headcount, so read it per player (or via `teamChemistry`), never raw.
    var leadershipScore: Int
    /// Raw SUM of negative toxic contributions across the roster. Same caveat
    /// as `leadershipScore`: it is a sum, not a rating.
    var toxicityScore: Int
    /// Human-readable log of recent events that affected chemistry.
    var recentEvents: [String]
}

// MARK: - Locker Room Engine

enum LockerRoomEngine {

    // MARK: - Calculate Chemistry

    /// Evaluates the full team chemistry based on player personalities, motivations,
    /// and how well players complement each other in the locker room.
    ///
    /// - Parameter collectEvents: build the human-readable `recentEvents` log.
    ///   The weekly league-wide morale pass (plan §2.9.1) runs this for all 32
    ///   rosters and only needs the number, so it opts out of ~50 string
    ///   interpolations per team per week.
    static func calculateChemistry(players: [Player], collectEvents: Bool = true) -> LockerRoomState {
        var leadershipScore = 0
        var toxicityScore = 0
        var events: [String] = []

        for player in players {
            let archetype = player.personality.archetype

            switch archetype {
            case .teamLeader:
                // High-morale leaders give a strong chemistry boost
                let contribution = player.morale >= 70 ? 8 : 4
                leadershipScore += contribution
                if contribution >= 8, collectEvents {
                    events.append("\(player.fullName) is leading the team with great energy.")
                }

            case .mentor:
                // Mentors uplift younger players; solid chemistry contributors
                let contribution = player.morale >= 60 ? 6 : 3
                leadershipScore += contribution
                if contribution >= 6, collectEvents {
                    events.append("\(player.fullName) is mentoring teammates and building trust.")
                }

            case .dramaQueen:
                // Drama Queens create friction, especially when unhappy
                let penalty = player.morale < 50 ? 8 : 4
                toxicityScore += penalty
                if penalty >= 8, collectEvents {
                    events.append("\(player.fullName) is stirring up drama in the locker room.")
                }

            case .fieryCompetitor:
                // Can be volatile — hurts chemistry when morale drops
                let penalty = player.morale < 45 ? 5 : 2
                toxicityScore += penalty
                if penalty >= 5, collectEvents {
                    events.append("\(player.fullName)'s intensity is creating locker room tension.")
                }

            case .loneWolf:
                // Lone Wolves neither help nor hurt; they stay in their lane
                break

            case .feelPlayer:
                // Feel Players amplify the current mood — good when happy, bad when not
                if player.morale >= 75 {
                    leadershipScore += 3
                    if collectEvents {
                        events.append("\(player.fullName)'s high energy is lifting the room.")
                    }
                } else if player.morale < 45 {
                    toxicityScore += 3
                    if collectEvents {
                        events.append("\(player.fullName)'s low mood is bringing others down.")
                    }
                }

            case .steadyPerformer, .quietProfessional:
                // Stable presences that provide a small passive boost
                leadershipScore += 1

            case .classClown:
                // Keeps spirits up but can be a mild distraction
                leadershipScore += 2
                if player.morale < 40 {
                    toxicityScore += 2
                }
            }
        }

        // Motivation alignment: players with matching motivations bond better
        let motivationGroups = Dictionary(grouping: players, by: { $0.personality.motivation })
        for (motivation, group) in motivationGroups.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where group.count >= 3 {
            leadershipScore += 2
            if collectEvents {
                events.append("Several \(motivation.rawValue.lowercased())-motivated players are bonding well.")
            }
        }

        // Chemistry: base 50, moved by the roster's net leadership PER PLAYER.
        //
        // This used to be `50 + leadershipScore - toxicityScore` on the raw
        // sums, which made chemistry scale with headcount instead of with the
        // room: a full 53-man roster of the nine equally likely archetypes nets
        // roughly +130, so every club in the league pinned at "Elite 100/100"
        // and no signing, cut or morale swing could move the bar. Normalising
        // per capita is what turns it back into a rating.
        let teamChemistry = chemistryRating(
            net: leadershipScore - toxicityScore,
            headcount: players.count
        )

        return LockerRoomState(
            teamChemistry: teamChemistry,
            leadershipScore: leadershipScore,
            toxicityScore: toxicityScore,
            recentEvents: Array(events.prefix(8)) // cap log to 8 entries
        )
    }

    /// Just the 0-100 chemistry number, without building the event log — the
    /// league-wide weekly morale pass only needs this.
    static func chemistryScore(players: [Player]) -> Int {
        calculateChemistry(players: players, collectEvents: false).teamChemistry
    }

    // MARK: - Chemistry Scale

    /// Chemistry points per point of NET (leadership − toxicity) contribution
    /// **per player**.
    ///
    /// Anchored on the per-player table in `calculateChemistry`, which tops out
    /// at ±8 a head: the best single presence a room can have is a happy Team
    /// Leader at +8, the worst an unhappy Drama Queen at −8, so net-per-head
    /// lives in [−8, +8]. 50 / 8 lays exactly that reachable range across the
    /// 0-100 dial either side of the base 50 — which is why this is 6.25 and
    /// not a round number. The clamp then belongs to a roster that is
    /// *entirely* leaders or *entirely* malcontents, not to every roster in
    /// the league.
    ///
    /// Sanity check against the ladder in `chemistryLabel`: the nine archetypes
    /// are drawn uniformly (`LeagueGenerator`) at a generated morale of 65-75,
    /// which averages ≈ +1.9 leadership and ≈ −0.7 toxicity a head. That lands
    /// a mixed room near 58 — inside the "Average" 50..<65 band, which is what
    /// an average locker room should read.
    static let chemistryPointsPerNetHead = 50.0 / 8.0

    /// Turns a raw leadership−toxicity sum into the 0-100 chemistry rating for
    /// a roster of `headcount` players. Single home for the formula so callers
    /// that hold the raw sums (the Locker Room "Net" column) can word them with
    /// the same maths the engine used.
    static func chemistryRating(net: Int, headcount: Int) -> Int {
        guard headcount > 0 else { return 50 }
        let raw = 50.0 + (Double(net) / Double(headcount)) * chemistryPointsPerNetHead
        return max(0, min(100, Int(raw.rounded())))
    }

    // MARK: - Morale Damping (plan §2.9.1)

    /// Morale every roster drifts back toward when nothing is happening. Keeps
    /// a bad season from spiralling to zero and a good one from pinning at 100.
    static let moraleBaseline = 70

    /// Hard cap on how far ONE game week may move a player's morale. The
    /// archetype table below can swing ±9 raw; damped it stays inside ±3 so a
    /// losing streak bleeds morale instead of hemorrhaging it.
    /// Widened from 3 when the weekly model stopped being "win or lose".
    ///
    /// Three was right for a single ±3 result term: it WAS the term, so the cap
    /// never bound. It became wrong the moment margin, expectation, streak,
    /// playing time and injury started contributing, because a saturated cap
    /// silently discards whichever input is added last — that is exactly how the
    /// withdrawn production term came to register only opposite to the result.
    /// Six leaves every term room to be heard while keeping a bad week's raw
    /// movement below a tenth of the 1-100 scale.
    static let weeklyMoraleSwingCap = 6

    /// A game decided by three points or fewer. The room reads it as "we were
    /// right there", and it moves morale about half what an ordinary result does.
    static let oneScoreMargin = 3

    /// Three scores. Past this the result stops being a game and starts being a
    /// statement about the team.
    static let blowoutMargin = 21

    /// Consecutive results before a run becomes a narrative. Two of anything is
    /// still noise; three is what a locker room, a press room and an owner all
    /// start calling a streak.
    static let streakThreshold = 3

    /// How many `.teamLeader`/`.mentor` men it takes to hold a room together.
    /// One respected veteran is a voice; two is a culture.
    static let leadershipQuorum = 2

    /// What that culture is worth against a bad week — a quarter off the drop,
    /// and nothing at all off a good one.
    static let leadershipDamping = 0.75

    /// How the week's result stood against what the club had a right to expect,
    /// read off records rather than ratings because that is how players, press
    /// and owners actually frame it.
    enum ResultExpectation {
        /// Clearly the better side on paper. Losing here costs extra.
        case favoured
        /// Clearly the weaker side. An upset lifts; the expected defeat is
        /// half-forgiven.
        case underdog
        /// Too close to call, or too early in the season for a record to mean
        /// anything. No adjustment.
        case even
    }

    /// Hard cap on the once-a-season settlement (`applyMoraleEffects`).
    static let seasonMoraleSwingCap = 8


    /// Applies one point of pull toward `moraleBaseline`, never overshooting it.
    /// Who is buried in his own position room this week.
    ///
    /// WHY NOT THE DEPTH CHART. `DepthChart` is stored on `Career`
    /// (`Career.depthChartData`), not on `Team` — it exists for the user's club
    /// and nowhere else. A depth-chart reading would therefore tax the human's
    /// roster and leave all 31 AI clubs untouched, which is precisely the
    /// asymmetry that sank the production term this replaces. Rank within the
    /// position room is the signal every club has.
    ///
    /// "Buried" is third or deeper at his own position: the starter and the man
    /// directly behind him both have a credible route onto the field, and the
    /// morale question here is not "am I the starter" — plenty of career
    /// backups are content — but "is there any path to playing at all".
    ///
    /// Ties on `overall` resolve by id so the answer is stable from week to
    /// week; a man should not drift in and out of unhappiness because two
    /// team-mates share a rating.
    private static func buriedPlayerIDs(in players: [Player]) -> Set<UUID> {
        var byPosition: [Position: [Player]] = [:]
        for player in players {
            byPosition[player.position, default: []].append(player)
        }
        var buried: Set<UUID> = []
        for (_, room) in byPosition {
            let ranked = room.sorted {
                $0.overall != $1.overall
                    ? $0.overall > $1.overall
                    : $0.id.uuidString < $1.id.uuidString
            }
            for (index, player) in ranked.enumerated() where index >= 2 {
                buried.insert(player.id)
            }
        }
        return buried
    }

    private static func reversionStep(from morale: Int) -> Int {
        if morale < moraleBaseline { return 1 }
        if morale > moraleBaseline { return -1 }
        return 0
    }

    // MARK: - Apply Morale Effects

    /// Season-end morale settlement: team record, locker-room chemistry, pay
    /// vs. market, and contract runway, filtered through the player's
    /// personality archetype.
    ///
    /// Runs ONCE per season (week 18, before contracts tick down), and the net
    /// swing is clamped to ±`seasonMoraleSwingCap` so a single call can never
    /// dominate the weekly loop that has been running all year.
    /// - Parameter salaryCap: the club's ACTUAL cap for the league year being
    ///   settled. The pay-vs-market term below calls
    ///   `ContractEngine.estimateMarketValue`, which defaults to the season-one
    ///   265 000 — so on a season-ten save every player was compared against a
    ///   market priced for a cap the league had long outgrown, salaries had
    ///   inflated with the real cap, and the "significantly underpaid" branch
    ///   had effectively stopped firing while the "great deal" branch fired for
    ///   nearly everybody. Required since task #87 / F5 — `WeekAdvancer` passes
    ///   `team.salaryCap`, and a missing cap is now a compile error rather than a
    ///   silent season-one price on a season-ten save.
    static func applyMoraleEffects(
        players: [Player],
        teamWins: Int,
        teamLosses: Int,
        chemistry: Int,
        salaryCap: Int
    ) {
        let totalGames = teamWins + teamLosses
        let winRate = totalGames > 0 ? Double(teamWins) / Double(totalGames) : 0.5

        for player in players {
            var delta = 0

            // --- Team record impact ---
            if winRate >= 0.7 {
                delta += 5
            } else if winRate >= 0.5 {
                delta += 2
            } else if winRate < 0.35 {
                delta -= 4
            } else {
                delta -= 1
            }

            // --- Chemistry impact ---
            //
            // Every boundary here is a `chemistryLabel` boundary, deliberately.
            // These numbers were written against a chemistry value that was
            // always 100 — the un-normalised roster sum saturated the ceiling on
            // any full roster — so the top branch fired for every club in the
            // league and the rest were unreachable. Normalising per capita put
            // an ordinary room at ~58, which made 75 mean "nobody", and a
            // threshold nobody meets is the same dead branch in the other
            // direction.
            //
            // Anchoring to the published ladder (Elite 80+, Strong 65+, Average
            // 50+, Shaky 35+, Toxic below) makes each branch mean the word the
            // rest of the app already shows the user for that number: a Strong
            // room is worth the big bonus, an Average one a nudge, a Toxic one
            // the full penalty. It also keeps the branch reachable in both
            // directions — measured travel is ~49 (drama-heavy) to ~89
            // (leader-stacked), so both ends are things a GM can build toward.
            if chemistry >= 65 {
                delta += 3
            } else if chemistry >= 50 {
                delta += 1
            } else if chemistry < 35 {
                delta -= 3
            } else {
                delta -= 1
            }

            // --- Contract situation: underpaid players lose morale ---
            let marketValue = ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)
            let payRatio = marketValue > 0 ? Double(player.annualSalary) / Double(marketValue) : 1.0
            if payRatio < 0.65 {
                // Significantly underpaid
                let contractPenalty = player.personality.motivation == .money ? -6 : -3
                delta += contractPenalty
            } else if payRatio >= 1.1 {
                // Overpaid or on a great deal
                let contractBonus = player.personality.motivation == .money ? 4 : 2
                delta += contractBonus
            }

            // --- Contract years remaining: upcoming free agency creates anxiety ---
            if player.contractYearsRemaining == 1 {
                if player.personality.motivation == .money {
                    delta -= 3 // Money-motivated players want security
                } else if player.personality.motivation == .loyalty {
                    delta -= 1
                }
            }

            // --- Personality modifiers ---
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players swing more dramatically in both directions
                delta = Int((Double(delta) * 1.5).rounded())

            case .dramaQueen:
                // Drama Queens amplify the swing and react to bad situations harder
                if delta < 0 {
                    delta = Int((Double(delta) * 1.4).rounded())
                }

            case .steadyPerformer, .quietProfessional:
                // Stable archetypes absorb volatility
                delta = Int((Double(delta) * 0.6).rounded())

            case .loneWolf:
                // Lone Wolves are less affected by team morale dynamics
                delta = Int((Double(delta) * 0.7).rounded())

            default:
                break
            }

            // Apply the damped, clamped morale update.
            delta = max(-seasonMoraleSwingCap, min(seasonMoraleSwingCap, delta))
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    // MARK: - Weekly Morale Update

    /// Small weekly morale adjustments tied to the most recent game result.
    /// Streaks compound these effects for feel players.
    ///
    /// Damping (plan §2.9.1) makes this safe to run every week for all 32
    /// rosters: the raw archetype swing is clamped to ±`weeklyMoraleSwingCap`
    /// and then one point of reversion toward `moraleBaseline` is applied. A
    /// .500 team therefore converges on ~70, a 4-13 team takes (4·+3 + 13·−3)
    /// = −27 from results and claws back +1 a week from reversion once it is
    /// under the baseline, so it settles around −10 on the season instead of
    /// spiralling, and no roster can pin itself at either end of the scale.
    ///
    /// NOTE on the `chemistry` term below: it is now genuinely conditional.
    /// While `calculateChemistry` summed raw scores every roster arrived here
    /// at a railed 100 and the `>= 70` branch fired for all 32 clubs every
    /// week; per capita a uniformly-mixed room sits near 58, so the term is 0
    /// unless the GM has actually built a leader-heavy (≥ 70) or malcontent-
    /// heavy (< 40) locker room.
    ///
    /// Callers pass only rosters that actually PLAYED this week (a bye week is
    /// not a loss) and skip holdouts, whose morale `HoldoutEngine` owns.
    ///
    /// WHY THERE IS NO PRODUCTION TERM. A week's box score used to feed a
    /// `.stats` reading here, and it was withdrawn deliberately. Three things
    /// were wrong with it and only the third is a matter of taste. It was added
    /// BEFORE the ±`weeklyMoraleSwingCap` clamp, which the result term has
    /// usually already spent, so it registered only in the direction OPPOSITE
    /// to the result — reward after a defeat, penalty after a win. It could
    /// only ever land on the user's club and his weekly opponent, because
    /// theirs is the one real box score a week produces, so no AI club paid it.
    /// And with `primaryTargetShare` at 1.0 the sim never fields WR4+, TE2,
    /// RB2, FB or QB2 at all, so the man it actually taxed was the backup who
    /// could not play his way out of it — measured at −4 to −14 morale over a
    /// 17-week season — rather than the starter whose usage dried up.
    ///
    /// A week moves morale on the RESULT, shaped by personality. That is the
    /// whole model, and it is why this function no longer takes a box score.
    static func weeklyMoraleUpdate(
        players: [Player],
        wonLastGame: Bool,
        chemistry: Int,
        margin: Int = 0,
        expectation: ResultExpectation = .even,
        streak: Int = 0
    ) {
        // Who is buried in his own position room, computed ONCE for the roster.
        let buried = buriedPlayerIDs(in: players)

        // Leaders damp a bad week rather than adding a good one (see below).
        let leaders = players.filter {
            $0.personality.archetype == .teamLeader || $0.personality.archetype == .mentor
        }.count

        for player in players {
            var delta = 0

            // 1. The result, shaped by HOW the game went. A three-point loss to
            //    a good side and a 38-point home humiliation are not the same
            //    week, and until now the engine could not tell them apart: it
            //    read both scores and threw the margin away on the line that
            //    wrote `home > away`.
            if abs(margin) >= blowoutMargin {
                delta = wonLastGame ? 3 : -3
            } else if abs(margin) <= oneScoreMargin {
                delta = wonLastGame ? 1 : -1
            } else {
                delta = wonLastGame ? 2 : -2
            }

            // 2. Against expectation. Losing to a side you should beat stings
            //    extra; beating one you should not lifts extra; losing to a
            //    clearly better side is half-forgiven. Expectation is read off
            //    records, which is how players and press actually frame it, and
            //    it stays `.even` early in the season when a record means
            //    nothing yet.
            switch expectation {
            case .favoured:
                if !wonLastGame { delta -= 1 }
            case .underdog:
                delta += 1          // upset win lifts; expected loss forgiven
            case .even:
                break
            }

            // 3. Trajectory. A locker room responds to the run, not the last
            //    result: one loss at 5-1 is noise, four straight is a crisis.
            //    Losing streaks bite harder than winning streaks lift, which is
            //    the asymmetry every dressing room in the sport reports.
            if streak <= -streakThreshold {
                delta -= min(2, abs(streak) - (streakThreshold - 1))
            } else if streak >= streakThreshold {
                delta += 1
            }

            // 4. Playing time — the single largest real-world morale driver for
            //    anyone who is not a starter, and the one the withdrawn
            //    production term was reaching for. A buried man is unhappy
            //    because he does not play, which is knowable from the roster
            //    for all 32 clubs; he was previously judged on a box score that
            //    structurally could not exist for him, on the user's club alone.
            //    A `.stats` man feels it twice over: usage is the whole of what
            //    he is measured by.
            if !player.isInjured && buried.contains(player.id) {
                delta -= player.personality.motivation == .stats ? 2 : 1
            }

            // 5. Injury. Being hurt is isolating and, for a man on an expiring
            //    deal, frightening — he is not in the building's week and his
            //    next contract is being decided without him.
            if player.isInjured { delta -= 1 }

            // Chemistry still has a mild weekly influence, on the same
            // `chemistryLabel` boundaries the season-end pass uses: a Strong
            // room (65+) is worth a point a week, a room below Average (<50)
            // costs one, and the ordinary Average club in between gets neither.
            // Symmetric around the band where most clubs actually sit, which
            // the old 70/40 pair was not once chemistry stopped being pinned
            // at 100.
            if chemistry >= 65 {
                delta += 1
            } else if chemistry < 50 {
                delta -= 1
            }

            // Personality-based weekly variance
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players ride the emotional rollercoaster week to week
                delta = wonLastGame ? delta + 3 : delta - 3

            case .dramaQueen:
                // Drama Queens are extra volatile — swings are steeper
                delta = wonLastGame ? delta + 2 : delta - 4

            case .steadyPerformer, .quietProfessional:
                // Dampen the weekly swing significantly
                delta = Int((Double(delta) * 0.4).rounded())

            case .teamLeader, .mentor:
                // Leaders stay grounded; winning gives a small extra lift
                delta = wonLastGame ? delta + 1 : delta - 1

            case .fieryCompetitor:
                // Competitors hate losing more than they love winning
                delta = wonLastGame ? delta + 1 : delta - 3

            default:
                break
            }

            // Money-motivated players on expiring contracts feel losses more
            if player.personality.motivation == .money && player.contractYearsRemaining <= 1 {
                if !wonLastGame { delta -= 2 }
            }

            // Winning-motivated players get an extra morale kick from victories
            if player.personality.motivation == .winning {
                delta = wonLastGame ? delta + 2 : delta - 2
            }

            // `.stats` is handled in term 4, by USAGE rather than by output.
            // The distinction is the whole lesson of the withdrawn production
            // term: a man buried at WR4 is unhappy because he does not play,
            // and that is true of him on every roster in the league whether or
            // not anyone wrote down a box score for his club that week.

            // 6. Leadership holds the room together in bad weeks. It damps the
            //    downside rather than adding a constant to both directions:
            //    what veterans demonstrably do is stop a bad run becoming a
            //    rout, not make a win sweeter.
            if leaders >= leadershipQuorum && delta < 0 {
                delta = Int((Double(delta) * leadershipDamping).rounded())
            }

            // Damp: cap the week's movement, then pull one point toward the
            // baseline — but NOT while a real streak is running. Reversion
            // exists so a season does not run away; applied during a streak it
            // cancels the very accumulation the streak term is there to build,
            // which is how a four-game collapse used to end the week roughly
            // where it started.
            delta = max(-weeklyMoraleSwingCap, min(weeklyMoraleSwingCap, delta))
            if abs(streak) < streakThreshold {
                delta += reversionStep(from: player.morale)
            }

            // Apply clamped morale update
            player.morale = max(1, min(100, player.morale + delta))
        }
    }


    // MARK: - Chemistry Color Helper

    /// Returns a string label for the chemistry level, used for display.
    static func chemistryLabel(_ chemistry: Int) -> String {
        switch chemistry {
        case 80...100: return "Elite"
        case 65..<80:  return "Strong"
        case 50..<65:  return "Average"
        case 35..<50:  return "Shaky"
        default:       return "Toxic"
        }
    }

    /// Bucketed morale tier for a single player.
    static func moraleTier(_ morale: Int) -> MoraleTier {
        switch morale {
        case 75...100: return .high
        case 45..<75:  return .medium
        default:       return .low
        }
    }

    enum MoraleTier: String {
        case high   = "High"
        case medium = "Medium"
        case low    = "Low"
    }
}

// MARK: - R25: Position Group Chemistry

extension LockerRoomEngine {

    /// Chemistry state of a position room: good / neutral / tense.
    enum GroupChemistryState: String {
        case good    = "Good"
        case neutral = "Neutral"
        case tense   = "Tense"
    }

    /// An active veteran-mentor → young-player pairing at the same position.
    /// The protégé develops slightly faster while the pairing holds.
    struct Mentorship: Identifiable {
        let mentor: Player
        let protege: Player
        var id: UUID { protege.id }
    }

    /// Why a position room is at risk of boiling over.
    enum ConflictReason: String {
        case hotheads = "Two volatile personalities in one room"
        case starEgo  = "Two stars, no clear number one"
    }

    /// A brewing conflict between two players in the same position group.
    struct GroupConflict: Identifiable {
        let playerA: Player
        let playerB: Player
        let reason: ConflictReason
        var id: String { "\(playerA.id)-\(playerB.id)-\(reason)" }
    }

    /// Aggregated chemistry snapshot for one position room.
    struct PositionGroupChemistry: Identifiable {
        let id: String
        let label: String
        let icon: String
        let players: [Player]
        let mentorships: [Mentorship]
        let conflicts: [GroupConflict]
        let state: GroupChemistryState

        var avgMorale: Int {
            guard !players.isEmpty else { return 50 }
            return players.map(\.morale).reduce(0, +) / players.count
        }
    }

    /// Shared position-room definition (same grouping the Locker Room UI uses).
    static let positionRooms: [(id: String, label: String, icon: String, positions: Set<Position>)] = [
        ("offense_skill", "Offense - Skill", "figure.american.football", [.QB, .RB, .FB, .WR, .TE]),
        ("offense_line",  "Offensive Line",  "shield.lefthalf.filled",  [.LT, .LG, .C, .RG, .RT]),
        ("defense_front", "Defensive Front", "shield.fill",             [.DE, .DT, .OLB, .MLB]),
        ("defense_back",  "Secondary",       "eye.fill",                [.CB, .FS, .SS]),
        ("special_teams", "Special Teams",   "figure.kickboxing",       [.K, .P])
    ]

    /// Finds active mentorships on a roster: a Mentor/Team Leader veteran
    /// (4+ years pro, leadership ≥ 65) paired with the greenest young player
    /// (≤ 2 years pro) at his own position. One protégé per mentor and vice versa.
    static func activeMentorships(players: [Player]) -> [Mentorship] {
        let mentors = players
            .filter {
                $0.personality.isMentor && $0.yearsPro >= 4
                && $0.mental.leadership >= 65 && !$0.isHoldingOut
            }
            .sorted { $0.mental.leadership > $1.mental.leadership }
        guard !mentors.isEmpty else { return [] }

        let youngsters = players.filter { $0.yearsPro <= 2 && !$0.isHoldingOut }
        var takenProteges = Set<UUID>()
        var result: [Mentorship] = []

        for mentor in mentors {
            let candidate = youngsters
                .filter {
                    $0.position == mentor.position
                    && $0.id != mentor.id
                    && !takenProteges.contains($0.id)
                }
                .min { ($0.yearsPro, -$0.overall) < ($1.yearsPro, -$1.overall) }
            guard let protege = candidate else { continue }
            takenProteges.insert(protege.id)
            result.append(Mentorship(mentor: mentor, protege: protege))
        }
        return result
    }

    /// IDs of every mentored young player across the league (one lookup for
    /// the weekly development pass). Grouped per team so mentors only ever
    /// tutor their own teammates.
    static func mentoredProtegeIDs(allPlayers: [Player]) -> Set<UUID> {
        var ids = Set<UUID>()
        let byTeam = Dictionary(grouping: allPlayers.filter { $0.teamID != nil }, by: { $0.teamID! })
        for (_, roster) in byTeam {
            for pairing in activeMentorships(players: roster) {
                ids.insert(pairing.protege.id)
            }
        }
        return ids
    }

    /// Detects brewing conflicts inside position rooms:
    /// 1. Two hotheads (Fiery Competitor / Drama Queen) share a room and at
    ///    least one is frustrated (morale < 65).
    /// 2. Two stars at the SAME position (both ≥ 82 OVR, within 2 points) —
    ///    no clear number one, egos collide.
    static func activeConflicts(players: [Player]) -> [GroupConflict] {
        var conflicts: [GroupConflict] = []

        for room in positionRooms {
            let members = players.filter { room.positions.contains($0.position) }
            guard members.count >= 2 else { continue }

            // 1) Hothead pair.
            let hotheads = members
                .filter {
                    $0.personality.archetype == .fieryCompetitor
                    || $0.personality.archetype == .dramaQueen
                }
                .sorted { $0.overall > $1.overall }
            if hotheads.count >= 2, hotheads.contains(where: { $0.morale < 65 }) {
                conflicts.append(GroupConflict(
                    playerA: hotheads[0], playerB: hotheads[1], reason: .hotheads
                ))
            }

            // 2) Star + star without a clear top dog at the same position.
            let byPosition = Dictionary(grouping: members, by: { $0.position })
            for position in byPosition.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let stars = (byPosition[position] ?? [])
                    .filter { $0.overall >= 82 }
                    .sorted { $0.overall > $1.overall }
                if stars.count >= 2, stars[0].overall - stars[1].overall <= 2 {
                    conflicts.append(GroupConflict(
                        playerA: stars[0], playerB: stars[1], reason: .starEgo
                    ))
                }
            }
        }
        return conflicts
    }

    /// Full chemistry snapshot per position room: members, mentorships,
    /// conflicts, and a good/neutral/tense verdict.
    static func positionGroupChemistry(players: [Player]) -> [PositionGroupChemistry] {
        let mentorships = activeMentorships(players: players)
        let conflicts = activeConflicts(players: players)

        return positionRooms.compactMap { room in
            let members = players.filter { room.positions.contains($0.position) }
            guard !members.isEmpty else { return nil }
            let memberIDs = Set(members.map(\.id))
            let roomMentorships = mentorships.filter { memberIDs.contains($0.mentor.id) }
            let roomConflicts = conflicts.filter { memberIDs.contains($0.playerA.id) }
            let avg = members.map(\.morale).reduce(0, +) / members.count

            let state: GroupChemistryState
            if !roomConflicts.isEmpty || avg < 45 {
                state = .tense
            } else if !roomMentorships.isEmpty || avg >= 70 {
                state = .good
            } else {
                state = .neutral
            }

            return PositionGroupChemistry(
                id: room.id,
                label: room.label,
                icon: room.icon,
                players: members,
                mentorships: roomMentorships,
                conflicts: roomConflicts,
                state: state
            )
        }
    }
}

// MARK: - R25: Weekly Locker Room Events

extension LockerRoomEngine {

    /// Rolls a weekly locker-room event for the user's team (~25 % of weeks).
    /// Candidates are built from personalities + morale + recent results, so
    /// the coach can always trace WHY something happened:
    /// - loss + frustrated hothead → outburst (choice: step in / let it play out)
    /// - win + team leader → players-only meeting (small team-wide boost)
    /// - mentor + young player at his position → mentor moment (protégé boost)
    /// - two stars without a clear number one → simmering tension (choice)
    /// - class clown after a loss → keeps the room loose (tiny lift)
    ///
    /// Informational events apply their morale effect immediately and return
    /// with `resolutionSummary` set; choice events return unresolved.
    static func rollWeeklyEvent(
        players: [Player],
        wonLastGame: Bool?,
        teamWins: Int,
        teamLosses: Int,
        week: Int,
        season: Int
    ) -> LockerRoomEvent? {
        guard !players.isEmpty else { return nil }
        guard Int.random(in: 1...100) <= 25 else { return nil }

        let losing = teamLosses > teamWins
        var candidates: [(weight: Int, build: () -> LockerRoomEvent)] = []

        // 1) Loss + frustrated hothead → outburst (choice).
        if wonLastGame == false {
            let frustrated = players
                .filter {
                    ($0.personality.archetype == .fieryCompetitor
                     || $0.personality.archetype == .dramaQueen)
                    && $0.morale < 55 && !$0.isHoldingOut
                }
                .sorted { $0.overall > $1.overall }
            if let hothead = frustrated.first {
                candidates.append((weight: 4 + (losing ? 2 : 0), build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .outburst,
                        title: "Locker Room Outburst",
                        detail: "\(hothead.fullName) (\(hothead.position.rawValue)) tore into teammates after the loss. The \(hothead.personality.archetype.displayName.lowercased()) is boiling over and the room is looking at you.",
                        playerIDs: [hothead.id],
                        playerNames: [hothead.fullName],
                        options: [
                            LockerRoomEventOption(
                                label: "Step In",
                                detail: "Pull \(hothead.lastName) aside and address it head-on. He won't like it, but the room sees accountability.",
                                targetMoraleDelta: -2,
                                teamMoraleDelta: +2,
                                outcomeSummary: "You confronted \(hothead.fullName) about the outburst — the room appreciated the accountability."
                            ),
                            LockerRoomEventOption(
                                label: "Let It Play Out",
                                detail: "Sometimes the room polices itself. \(hothead.lastName) keeps his edge, but teammates may feel it went unchecked.",
                                targetMoraleDelta: +1,
                                teamMoraleDelta: -3,
                                outcomeSummary: "The outburst by \(hothead.fullName) went unaddressed — some players felt it was let slide."
                            )
                        ]
                    )
                }))
            }
        }

        // 2) Win + team leader → players-only meeting (auto boost).
        if wonLastGame == true, teamWins >= teamLosses {
            let leaders = players
                .filter { $0.personality.archetype == .teamLeader && $0.morale >= 60 }
                .sorted { $0.mental.leadership > $1.mental.leadership }
            if let leader = leaders.first {
                candidates.append((weight: 3, build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .playersOnlyMeeting,
                        title: "Players-Only Meeting",
                        detail: "\(leader.fullName) called a players-only meeting to keep the streak alive. Voices stayed low, standards stayed high.",
                        playerIDs: [leader.id],
                        playerNames: [leader.fullName],
                        resolutionSummary: "The meeting galvanized the room — team morale ticked up."
                    )
                }))
            }
        }

        // 3) Mentor moment (auto): protégé gets a lift.
        let mentorships = activeMentorships(players: players)
        if let pairing = mentorships.first {
            candidates.append((weight: 2, build: {
                LockerRoomEvent(
                    season: season, week: week, kind: .mentorMoment,
                    title: "Under His Wing",
                    detail: "\(pairing.mentor.fullName) has been staying late with \(pairing.protege.fullName), walking him through film and pro habits.",
                    playerIDs: [pairing.protege.id],
                    playerNames: [pairing.mentor.fullName, pairing.protege.fullName],
                    resolutionSummary: "\(pairing.protege.fullName) is soaking it up — his confidence is growing."
                )
            }))
        }

        // 4) Simmering star tension (choice).
        let conflicts = activeConflicts(players: players)
        if let conflict = conflicts.first {
            candidates.append((weight: 2 + (losing ? 1 : 0), build: {
                LockerRoomEvent(
                    season: season, week: week, kind: .starTension,
                    title: "Tension in the Room",
                    detail: "\(conflict.playerA.fullName) and \(conflict.playerB.fullName) are circling each other — \(conflict.reason.rawValue.lowercased()). Beat writers are starting to ask questions.",
                    playerIDs: [conflict.playerA.id, conflict.playerB.id],
                    playerNames: [conflict.playerA.fullName, conflict.playerB.fullName],
                    options: [
                        LockerRoomEventOption(
                            label: "Define Roles",
                            detail: "Set the pecking order in front of the room. Not everyone will love it, but everyone will know where they stand.",
                            targetMoraleDelta: -1,
                            teamMoraleDelta: +2,
                            outcomeSummary: "You defined the roles publicly — the room has clarity, even if the stars grumbled."
                        ),
                        LockerRoomEventOption(
                            label: "Let Them Compete",
                            detail: "Competition sharpens stars — but teammates may start picking sides.",
                            targetMoraleDelta: +2,
                            teamMoraleDelta: -2,
                            outcomeSummary: "You let the rivalry burn — the stars are pushing each other, but the room is picking sides."
                        )
                    ]
                )
            }))
        }

        // 5) Class clown keeps things loose after a loss (auto).
        if wonLastGame == false {
            let clowns = players.filter { $0.personality.archetype == .classClown }
            if let clown = clowns.max(by: { $0.morale < $1.morale }) {
                candidates.append((weight: 1, build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .moodLift,
                        title: "Keeping It Loose",
                        detail: "After a rough Sunday, \(clown.fullName) had the room laughing again by Wednesday's walkthrough.",
                        playerIDs: [clown.id],
                        playerNames: [clown.fullName],
                        resolutionSummary: "The mood lightened — a short week feels a little shorter."
                    )
                }))
            }
        }

        // Weighted pick.
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var roll = Int.random(in: 1...totalWeight)
        var chosen: LockerRoomEvent?
        for candidate in candidates {
            roll -= candidate.weight
            if roll <= 0 {
                chosen = candidate.build()
                break
            }
        }
        guard let event = chosen else { return nil }

        // Informational events apply their (small) effect right away.
        if !event.options.isEmpty { return event }
        switch event.kind {
        case .playersOnlyMeeting:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +3, teamDelta: +2, players: players)
        case .mentorMoment:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +3, teamDelta: 0, players: players)
        case .moodLift:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +2, teamDelta: +1, players: players)
        case .outburst, .starTension:
            break // choice events never reach here
        }
        return event
    }

    /// Applies a resolved option's morale deltas: involved players get the
    /// target delta, everyone else on the roster the team delta. Clamped 1-100.
    static func applyEventEffects(
        targetIDs: [UUID],
        targetDelta: Int,
        teamDelta: Int,
        players: [Player]
    ) {
        for player in players {
            let delta = targetIDs.contains(player.id) ? targetDelta : teamDelta
            guard delta != 0 else { continue }
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    /// Applies the chosen option to the roster and returns the resolved event
    /// for logging (caller persists it on the career).
    static func resolve(
        event: LockerRoomEvent,
        option: LockerRoomEventOption,
        players: [Player]
    ) -> LockerRoomEvent {
        applyEventEffects(
            targetIDs: event.playerIDs,
            targetDelta: option.targetMoraleDelta,
            teamDelta: option.teamMoraleDelta,
            players: players
        )
        var resolved = event
        resolved.resolutionSummary = option.outcomeSummary
        return resolved
    }
}
