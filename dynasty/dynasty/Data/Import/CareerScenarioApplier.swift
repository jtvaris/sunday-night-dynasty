import Foundation

/// R40 — Scenario starts.
///
/// Applies a `CareerScenario` on top of a freshly generated league, BEFORE
/// anything is inserted into the model context. A scenario never introduces
/// new systems: it only re-parametrizes what `LeagueGenerator` produced —
/// the chosen team's roster strength, the owner's persisted traits (which the
/// R31 `OwnerPersonaEngine` deterministically derives an archetype from),
/// draft-pick ownership, and the cap sheet. Season goals then follow
/// automatically from the modified owner at the season kickoff.
enum CareerScenarioApplier {

    /// Applies the scenario to the chosen team. Call after league generation
    /// and before model-context insertion.
    /// - Parameters:
    ///   - scenario: The selected scenario card.
    ///   - chosenTeam: The user's team.
    ///   - owner: The chosen team's owner (traits are overwritten in place).
    ///   - teamPlayers: The chosen team's generated roster.
    ///   - draftPicks: ALL generated draft picks (ownership is edited in place).
    ///   - allTeams: All 32 teams (extra-pick donors are drawn from here).
    static func apply(
        _ scenario: CareerScenario,
        chosenTeam: Team,
        owner: Owner,
        teamPlayers: [Player],
        draftPicks: [DraftPick],
        allTeams: [Team]
    ) {
        switch scenario {
        case .rebuild:
            applyRebuild(
                chosenTeam: chosenTeam, owner: owner,
                teamPlayers: teamPlayers, draftPicks: draftPicks, allTeams: allTeams
            )
        case .winNow:
            applyWinNow(
                chosenTeam: chosenTeam, owner: owner,
                teamPlayers: teamPlayers, draftPicks: draftPicks, allTeams: allTeams
            )
        case .capHell:
            applyCapHell(chosenTeam: chosenTeam, owner: owner, teamPlayers: teamPlayers)
        }

        // Any scenario can change salaries — keep the cap ledger truthful.
        chosenTeam.currentCapUsage = teamPlayers.reduce(0) { $0 + $1.annualSalary }
    }

    // MARK: - Rebuild

    /// Weakest roster + extra premium picks + a patient, hands-off owner.
    private static func applyRebuild(
        chosenTeam: Team,
        owner: Owner,
        teamPlayers: [Player],
        draftPicks: [DraftPick],
        allTeams: [Team]
    ) {
        // Stripped-down roster: every player takes a broad talent hit.
        for player in teamPlayers {
            shiftAttributes(of: player, by: -8)
        }

        // Patient Builder owner (R31 archetype: meddling < 65, !prefersWinNow).
        owner.patience = Int.random(in: 8...9)
        owner.prefersWinNow = false
        owner.meddling = min(owner.meddling, 25)
        owner.spendingWillingness = max(45, min(owner.spendingWillingness, 60))

        // War chest: acquire one extra pick in each of rounds 1-3 of the
        // upcoming draft from three distinct AI teams (modeled as past trades,
        // so pick numbers stay coherent).
        var donorIDs = Set<UUID>()
        for round in 1...3 {
            let candidates = draftPicks.filter {
                $0.round == round
                    && $0.currentTeamID != chosenTeam.id
                    && !donorIDs.contains($0.currentTeamID)
            }
            guard let pick = candidates.randomElement() else { continue }
            donorIDs.insert(pick.currentTeamID)
            pick.currentTeamID = chosenTeam.id
        }
    }

    // MARK: - Win Now

    /// Star-heavy but aging roster whose premium picks are already spent,
    /// owned by a Win-Now Tycoon (R31 archetype).
    private static func applyWinNow(
        chosenTeam: Team,
        owner: Owner,
        teamPlayers: [Player],
        draftPicks: [DraftPick],
        allTeams: [Team]
    ) {
        // Boost the core: top 15 by overall gain talent, top 10 also age into
        // the tail end of their primes (the closing window).
        let byOverall = teamPlayers.sorted { $0.overall > $1.overall }
        for (index, player) in byOverall.prefix(15).enumerated() {
            shiftAttributes(of: player, by: +5)
            if index < 10 {
                player.age = min(34, player.age + Int.random(in: 2...3))
                player.yearsPro = max(player.yearsPro, player.age - 22)
            }
        }

        // Win-Now Tycoon (R31: prefersWinNow + spending >= 55, meddling < 65).
        owner.patience = Int.random(in: 2...3)
        owner.prefersWinNow = true
        owner.spendingWillingness = Int.random(in: 85...95)
        owner.meddling = min(owner.meddling, 60)

        // The bill for the stars: this year's own round 1-2 picks were
        // shipped out. Each goes to a random other franchise.
        let otherTeams = allTeams.filter { $0.id != chosenTeam.id }
        for pick in draftPicks
        where pick.currentTeamID == chosenTeam.id && pick.round <= 2 {
            if let receiver = otherTeams.randomElement() {
                pick.currentTeamID = receiver.id
            }
        }
    }

    // MARK: - Cap Hell

    /// Good roster, catastrophic books: salaries inflated past the cap and
    /// the biggest deals locked in for years.
    private static func applyCapHell(
        chosenTeam: Team,
        owner: Owner,
        teamPlayers: [Player]
    ) {
        // The talent is real: the core gets a modest bump.
        let byOverall = teamPlayers.sorted { $0.overall > $1.overall }
        for player in byOverall.prefix(12) {
            shiftAttributes(of: player, by: +3)
        }

        // Inflate the ledger to ~105-108% of the cap.
        let cap = chosenTeam.salaryCap
        let target = Int(Double(cap) * Double.random(in: 1.05...1.08))
        let currentTotal = teamPlayers.reduce(0) { $0 + $1.annualSalary }
        if currentTotal > 0 {
            let ratio = Double(target) / Double(currentTotal)
            for player in teamPlayers {
                player.annualSalary = max(750, Int((Double(player.annualSalary) * ratio).rounded()))
            }
        }

        // The ten biggest contracts are long-term problems, not expiring relief.
        let bySalary = teamPlayers.sorted { $0.annualSalary > $1.annualSalary }
        for player in bySalary.prefix(10) {
            player.contractYearsRemaining = max(player.contractYearsRemaining, Int.random(in: 3...4))
        }

        // A measured owner: neither savior nor executioner.
        owner.patience = Int.random(in: 4...6)
    }

    // MARK: - Attribute Shifting

    private static func shift(_ value: Int, _ delta: Int) -> Int {
        max(25, min(99, value + delta))
    }

    /// Shifts every physical, mental, and position-specific attribute of the
    /// player by `delta`, clamped to 25...99.
    private static func shiftAttributes(of player: Player, by delta: Int) {
        player.physical.speed = shift(player.physical.speed, delta)
        player.physical.acceleration = shift(player.physical.acceleration, delta)
        player.physical.strength = shift(player.physical.strength, delta)
        player.physical.agility = shift(player.physical.agility, delta)
        player.physical.stamina = shift(player.physical.stamina, delta)
        player.physical.durability = shift(player.physical.durability, delta)

        player.mental.awareness = shift(player.mental.awareness, delta)
        player.mental.decisionMaking = shift(player.mental.decisionMaking, delta)
        player.mental.clutch = shift(player.mental.clutch, delta)
        player.mental.workEthic = shift(player.mental.workEthic, delta)
        player.mental.coachability = shift(player.mental.coachability, delta)
        player.mental.leadership = shift(player.mental.leadership, delta)

        switch player.positionAttributes {
        case .quarterback(let qb):
            player.positionAttributes = .quarterback(QBAttributes(
                armStrength: shift(qb.armStrength, delta),
                accuracyShort: shift(qb.accuracyShort, delta),
                accuracyMid: shift(qb.accuracyMid, delta),
                accuracyDeep: shift(qb.accuracyDeep, delta),
                pocketPresence: shift(qb.pocketPresence, delta),
                scrambling: shift(qb.scrambling, delta)
            ))
        case .wideReceiver(let wr):
            player.positionAttributes = .wideReceiver(WRAttributes(
                routeRunning: shift(wr.routeRunning, delta),
                catching: shift(wr.catching, delta),
                release: shift(wr.release, delta),
                spectacularCatch: shift(wr.spectacularCatch, delta)
            ))
        case .runningBack(let rb):
            player.positionAttributes = .runningBack(RBAttributes(
                vision: shift(rb.vision, delta),
                elusiveness: shift(rb.elusiveness, delta),
                breakTackle: shift(rb.breakTackle, delta),
                receiving: shift(rb.receiving, delta)
            ))
        case .tightEnd(let te):
            player.positionAttributes = .tightEnd(TEAttributes(
                blocking: shift(te.blocking, delta),
                catching: shift(te.catching, delta),
                routeRunning: shift(te.routeRunning, delta),
                speed: shift(te.speed, delta)
            ))
        case .offensiveLine(let ol):
            player.positionAttributes = .offensiveLine(OLAttributes(
                runBlock: shift(ol.runBlock, delta),
                passBlock: shift(ol.passBlock, delta),
                pull: shift(ol.pull, delta),
                anchor: shift(ol.anchor, delta)
            ))
        case .defensiveLine(let dl):
            player.positionAttributes = .defensiveLine(DLAttributes(
                passRush: shift(dl.passRush, delta),
                blockShedding: shift(dl.blockShedding, delta),
                powerMoves: shift(dl.powerMoves, delta),
                finesseMoves: shift(dl.finesseMoves, delta)
            ))
        case .linebacker(let lb):
            player.positionAttributes = .linebacker(LBAttributes(
                tackling: shift(lb.tackling, delta),
                zoneCoverage: shift(lb.zoneCoverage, delta),
                manCoverage: shift(lb.manCoverage, delta),
                blitzing: shift(lb.blitzing, delta)
            ))
        case .defensiveBack(let db):
            player.positionAttributes = .defensiveBack(DBAttributes(
                manCoverage: shift(db.manCoverage, delta),
                zoneCoverage: shift(db.zoneCoverage, delta),
                press: shift(db.press, delta),
                ballSkills: shift(db.ballSkills, delta)
            ))
        case .kicking(let k):
            player.positionAttributes = .kicking(KickingAttributes(
                kickPower: shift(k.kickPower, delta),
                kickAccuracy: shift(k.kickAccuracy, delta)
            ))
        }
    }
}
