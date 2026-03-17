import Foundation

/// Manages owner satisfaction, firing decisions, and post-firing job offers.
enum OwnerSatisfactionEngine {

    // MARK: - Satisfaction Update

    /// Updates the owner's satisfaction based on team performance, media, and personality.
    static func updateSatisfaction(
        owner: Owner,
        team: Team,
        career: Career,
        newsItems: [NewsItem]
    ) {
        var delta = 0

        // --- Win/Loss Impact ---
        let totalGames = team.wins + team.losses
        if totalGames > 0 {
            let winPct = Double(team.wins) / Double(totalGames)

            if owner.prefersWinNow {
                // Win-now owners have higher expectations
                if winPct >= 0.75 {
                    delta += 5
                } else if winPct >= 0.55 {
                    delta += 2
                } else if winPct < 0.40 {
                    delta -= 6
                } else if winPct < 0.50 {
                    delta -= 3
                }
            } else {
                // Patient/rebuilding owners are more forgiving
                if winPct >= 0.65 {
                    delta += 4
                } else if winPct >= 0.50 {
                    delta += 1
                } else if winPct < 0.30 {
                    delta -= 4
                } else if winPct < 0.45 {
                    delta -= 2
                }
            }
        }

        // --- Losing Streak Detection ---
        // Approximate streak from recent record: if losses > wins + 3, treat as a streak
        let lossMargin = team.losses - team.wins
        if lossMargin >= 5 {
            delta -= 4  // Severe losing accelerates decline
        } else if lossMargin >= 3 {
            delta -= 2
        }

        // --- Patience Modifier ---
        // Low patience (1-3) amplifies negative deltas; high patience (8-10) softens them
        if delta < 0 {
            let patienceMultiplier: Double = {
                switch owner.patience {
                case 1...3:  return 1.5
                case 4...6:  return 1.0
                case 7...10: return 0.6
                default:     return 1.0
                }
            }()
            delta = Int((Double(delta) * patienceMultiplier).rounded())
        }

        // --- Media Market Amplification ---
        // Large-market teams get more scrutiny; negative events hit harder
        let mediaPressure = team.mediaMarket.mediaPressureMultiplier
        if delta < 0 {
            delta = Int((Double(delta) * mediaPressure).rounded())
        }

        // --- Meddling ---
        // High-meddling owners lose extra satisfaction when things go poorly
        if delta < 0 && owner.meddling > 60 {
            delta -= 1
        }

        // --- News Sentiment Impact ---
        let negativeNewsCount = newsItems.filter {
            $0.sentiment == .negative && $0.relatedTeamID == team.id
        }.count
        let positiveNewsCount = newsItems.filter {
            $0.sentiment == .positive && $0.relatedTeamID == team.id
        }.count

        delta -= Int((Double(negativeNewsCount) * mediaPressure).rounded())
        delta += positiveNewsCount

        // --- Milestone Bonuses ---
        if career.playoffAppearances > 0 && career.currentPhase == .playoffs {
            delta += 10  // Playoff appearance is a big boost
        }
        if career.championships > 0 {
            delta += 25  // Championship is a massive boost
        }

        // Apply the delta and clamp to 0-100
        owner.satisfaction = min(100, max(0, owner.satisfaction + delta))
    }

    // MARK: - Firing Check

    /// Determines whether the owner fires the head coach/GM this offseason.
    /// Returns `true` if the career is over with this team.
    static func checkFiring(owner: Owner, career: Career) -> Bool {
        let satisfaction = owner.satisfaction

        // Patience-adjusted thresholds
        let criticalThreshold = max(10, 20 - owner.patience)
        let dangerThreshold = max(20, 35 - owner.patience)

        // Critical zone: satisfaction below critical threshold
        if satisfaction < criticalThreshold {
            // Very high chance of firing (70-95%)
            let firingChance = 70 + (criticalThreshold - satisfaction) * 2
            return Int.random(in: 1...100) <= min(firingChance, 95)
        }

        // Danger zone: satisfaction below danger threshold AND multiple losing seasons
        if satisfaction < dangerThreshold {
            let hasLosingRecord = career.totalLosses > career.totalWins
            let multipleLosingSeasonsLikely = career.currentSeason >= 2 && hasLosingRecord

            if multipleLosingSeasonsLikely {
                // Moderate chance of firing (30-50%)
                let firingChance = 30 + (dangerThreshold - satisfaction)
                return Int.random(in: 1...100) <= min(firingChance, 50)
            }
        }

        return false
    }

    // MARK: - Job Offers After Firing

    /// Generates 1-5 job offers based on the career's reputation after being fired.
    static func generateJobOffers(
        career: Career,
        allTeams: [Team]
    ) -> [(team: Team, offer: String)] {
        let reputation = career.reputation

        // Number of offers scales with reputation
        let offerCount: Int = {
            switch reputation {
            case 80...99: return min(5, allTeams.count)
            case 60...79: return min(4, allTeams.count)
            case 40...59: return min(3, allTeams.count)
            case 20...39: return min(2, allTeams.count)
            default:      return min(1, allTeams.count)
            }
        }()

        // Sort teams by attractiveness (inverse of wins — worse teams are more likely to have openings)
        let sortedTeams = allTeams
            .filter { $0.id != career.teamID }  // Exclude team that just fired you
            .sorted { $0.wins < $1.wins }

        var offers: [(team: Team, offer: String)] = []

        for i in 0..<min(offerCount, sortedTeams.count) {
            let team = sortedTeams[i]
            let offer = generateOfferDescription(team: team, reputation: reputation)
            offers.append((team: team, offer: offer))
        }

        // High-reputation coaches also get offers from decent teams
        if reputation >= 70 {
            let goodTeams = sortedTeams.filter { $0.wins >= $0.losses }.prefix(2)
            for team in goodTeams {
                if !offers.contains(where: { $0.team.id == team.id }) && offers.count < 5 {
                    let offer = generateOfferDescription(team: team, reputation: reputation)
                    offers.append((team: team, offer: offer))
                }
            }
        }

        return Array(offers.prefix(5))
    }

    // MARK: - Private Helpers

    private static func generateOfferDescription(team: Team, reputation: Int) -> String {
        let record = team.record
        let market = team.mediaMarket

        if team.wins >= team.losses {
            return "The \(team.fullName) (\(record)) are a competitive \(market.rawValue.lowercased())-market team looking for a proven leader to push them over the top. Expectations are high."
        } else if team.wins + team.losses > 0 && Double(team.wins) / Double(team.wins + team.losses) >= 0.35 {
            return "The \(team.fullName) (\(record)) are a \(market.rawValue.lowercased())-market team in need of a new direction. The roster has some pieces but needs a clear vision."
        } else {
            return "The \(team.fullName) (\(record)) are deep in a rebuild. This \(market.rawValue.lowercased())-market franchise offers low pressure and time to develop young talent."
        }
    }
}
