import Foundation
import SwiftData

// MARK: - FacilityEngine (TODO §5.4)

/// Facility investment: the one lever the owner's chequebook has on the
/// football side that is not a salary.
///
/// Three independent tracks, each on a 1-3 tier ladder:
///
/// | Track            | Tier 1     | Tier 2 (default) | Tier 3            |
/// |------------------|------------|------------------|-------------------|
/// | Training complex | Dated      | League Standard  | State-of-the-Art  |
/// | Medical wing     | Dated      | League Standard  | State-of-the-Art  |
/// | Recovery centre  | Dated      | League Standard  | State-of-the-Art  |
///
/// **Tier 2 is neutral on purpose.** Every multiplier this engine returns is
/// exactly `1.0` (or `0` for the flat fatigue bonus) at all-tier-2, and tier 2
/// is the stored default on `Owner`. A save written before facilities existed
/// therefore develops, breaks down and heals exactly as it did — the system
/// only bites once somebody spends up or lets the building rot.
///
/// Effects, and who applies them:
/// - **Development** — `developmentMultiplier(teamID:owners:)`, 0.92…1.08,
///   multiplied into the offseason development pass by the caller.
/// - **Injury frequency** — `MedicalEngine.injuryCheck` (medical wing).
/// - **Recovery speed** — `MedicalEngine.recoveryWeeks` / `processWeeklyRehab`
///   / `weeklyFatigueRecovery` (recovery centre).
/// - **Owner meeting** — `ownerMeetingLine(owner:)`.
///
/// Money: upkeep is an ANNUAL running cost in thousands, drawn from a facility
/// envelope the owner grants separately from the staff-salary envelope
/// (`coachingBudget` + `scoutingBudget` + `medicalBudget`) — those three pots
/// are committed to people, and a stadium upgrade cannot be paid for by not
/// paying the physio.
enum FacilityEngine {

    // MARK: - Tracks & Tiers

    /// The three independent investment tracks.
    enum Track: String, CaseIterable, Identifiable, Codable {
        case training
        case medical
        case recovery

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .training: return "Training Complex"
            case .medical:  return "Medical Wing"
            case .recovery: return "Recovery Centre"
            }
        }

        /// SF Symbol used in the facilities card.
        var icon: String {
            switch self {
            case .training: return "dumbbell.fill"
            case .medical:  return "cross.case.fill"
            case .recovery: return "bed.double.fill"
            }
        }

        var caption: String {
            switch self {
            case .training:
                return "Weight room, indoor field, sports science. Drives how fast players develop."
            case .medical:
                return "Imaging, surgeons on call, load monitoring. Drives how often players get hurt."
            case .recovery:
                return "Cryo, hydrotherapy, sleep programme. Drives how fast they heal and freshen up."
            }
        }
    }

    /// Lowest / highest tier a track can hold.
    static let minTier = 1
    static let maxTier = 3

    /// Display name for a tier.
    static func tierName(_ tier: Int) -> String {
        switch clampTier(tier) {
        case 1:  return "Dated"
        case 2:  return "League Standard"
        default: return "State-of-the-Art"
        }
    }

    static func clampTier(_ tier: Int) -> Int {
        min(maxTier, max(minTier, tier))
    }

    // MARK: - Levels

    /// A club's three tiers, read off an `Owner` (or the neutral default when
    /// there is no owner row to read).
    struct Levels: Equatable {
        var training: Int
        var medical: Int
        var recovery: Int

        /// All-tier-2: every multiplier below returns exactly neutral.
        static let standard = Levels(training: 2, medical: 2, recovery: 2)

        subscript(track: Track) -> Int {
            get {
                switch track {
                case .training: return training
                case .medical:  return medical
                case .recovery: return recovery
                }
            }
            set {
                let value = FacilityEngine.clampTier(newValue)
                switch track {
                case .training: training = value
                case .medical:  medical = value
                case .recovery: recovery = value
                }
            }
        }
    }

    /// Reads a club's tiers off its owner. A `nil` owner — an unlinked or
    /// legacy row — reads as league standard, i.e. fully neutral.
    static func levels(for owner: Owner?) -> Levels {
        guard let owner else { return .standard }
        return Levels(
            training: clampTier(owner.trainingFacilityLevel),
            medical: clampTier(owner.medicalFacilityLevel),
            recovery: clampTier(owner.recoveryFacilityLevel)
        )
    }

    /// Writes tiers back onto an owner and drops the resolver cache so the
    /// medical path picks the change up on its next roll.
    static func apply(_ levels: Levels, to owner: Owner) {
        owner.trainingFacilityLevel = clampTier(levels.training)
        owner.medicalFacilityLevel = clampTier(levels.medical)
        owner.recoveryFacilityLevel = clampTier(levels.recovery)
        invalidateCache()
    }

    // MARK: - Effects

    /// Development speed multiplier for a club, **0.92…1.08**.
    ///
    /// PINNED API — the offseason development pass calls exactly this shape:
    /// it holds a team id and a flat owner list, never a `Team`. An owner that
    /// has not been linked to its club yet (`Owner.teamID == nil`, e.g. a save
    /// from before facilities shipped that has not run a pass yet) is not in
    /// the list as far as this lookup is concerned, and the club develops at
    /// the neutral `1.0` it always did.
    static func developmentMultiplier(teamID: UUID, owners: [Owner]) -> Double {
        developmentMultiplier(levels: levels(for: owners.first { $0.teamID == teamID }))
    }

    /// The training complex carries the multiplier; the recovery centre adds a
    /// smaller share, because a body that never fully recovers cannot bank the
    /// work it did. Tier 2 on both = exactly 1.0.
    static func developmentMultiplier(levels: Levels) -> Double {
        let training: Double
        switch levels.training {
        case 1:  training = -0.06
        case 2:  training = 0.0
        default: training = 0.06
        }
        let recovery: Double
        switch levels.recovery {
        case 1:  recovery = -0.02
        case 2:  recovery = 0.0
        default: recovery = 0.02
        }
        return 1.0 + training + recovery
    }

    /// Injury-frequency multiplier applied to the per-player weekly injury
    /// roll. Driven by the medical wing alone — availability is a medical
    /// department's job, and keeping it single-track means the number stays
    /// readable in the facilities card ("−8 % injuries").
    static func injuryRiskMultiplier(levels: Levels) -> Double {
        switch levels.medical {
        case 1:  return 1.06
        case 2:  return 1.0
        default: return 0.92
        }
    }

    /// Multiplier on the prognosis an injury gets (`MedicalEngine.recoveryWeeks`).
    /// Below 1.0 = shorter absences. Driven by the recovery centre.
    static func recoveryWeeksMultiplier(levels: Levels) -> Double {
        switch levels.recovery {
        case 1:  return 1.08
        case 2:  return 1.0
        default: return 0.90
        }
    }

    /// Additive shift on the weekly rehab roll's ahead-of-schedule chance
    /// (and, mirrored, its setback chance). ±0.03 at the extremes.
    static func rehabOddsShift(levels: Levels) -> Double {
        switch levels.recovery {
        case 1:  return -0.03
        case 2:  return 0.0
        default: return 0.03
        }
    }

    /// Flat extra fatigue points recovered per week. 0 at league standard.
    static func fatigueRecoveryBonus(levels: Levels) -> Int {
        switch levels.recovery {
        case 1:  return -3
        case 2:  return 0
        default: return 4
        }
    }

    // MARK: - Money

    /// Annual upkeep of one tier, in thousands. The jumps are deliberately
    /// steep: tier 3 on all three tracks ($19.2M/yr) is only affordable to an
    /// owner who is close to maxed on spending willingness.
    static func annualCost(tier: Int) -> Int {
        switch clampTier(tier) {
        case 1:  return 800
        case 2:  return 2_600
        default: return 6_400
        }
    }

    /// Total annual upkeep of a club's three tracks, in thousands.
    static func upkeep(levels: Levels) -> Int {
        Track.allCases.reduce(0) { $0 + annualCost(tier: levels[$1]) }
    }

    static func upkeep(owner: Owner?) -> Int {
        upkeep(levels: levels(for: owner))
    }

    /// What the owner is willing to sink into buildings each year, in
    /// thousands. Spending willingness dominates; satisfaction moves it ±10 %
    /// because a happy owner writes cheques and an unhappy one stops.
    ///
    /// Calibrated against the shipped owner table, where willingness runs
    /// ~35-75. At the bottom of that band (35, satisfaction 70) the envelope is
    /// ~$10.5M: league standard on all three tracks ($7.8M) is comfortable, one
    /// state-of-the-art track ($11.6M total) is not. At 55 the club can afford
    /// exactly one; at 75 it can afford two. **Nobody in the shipped league can
    /// run all three at state-of-the-art** ($19.2M) — that takes a willingness
    /// near the 99 ceiling, so the top tier is always a choice about which
    /// building matters, never a checklist to complete.
    static func annualBudget(owner: Owner?) -> Int {
        guard let owner else { return upkeep(levels: .standard) }
        let base = 4_500 + owner.spendingWillingness * 160
        let mood = 0.90 + Double(max(0, min(100, owner.satisfaction))) / 500.0
        return Int((Double(base) * mood).rounded())
    }

    /// Can this club move `track` to `tier` and still cover the upkeep?
    static func canAfford(owner: Owner, track: Track, tier: Int) -> Bool {
        var proposed = levels(for: owner)
        proposed[track] = tier
        return upkeep(levels: proposed) <= annualBudget(owner: owner)
    }

    // MARK: - Owner Linkage

    /// Stamps `Owner.teamID` from the team side. `Team.owner` is the only
    /// edge that exists in the schema, so this is the only place the link can
    /// be established for the whole league at once. Idempotent.
    ///
    /// - Returns: how many owners were newly linked.
    @discardableResult
    static func linkOwners(teams: [Team]) -> Int {
        var linked = 0
        for team in teams {
            guard let owner = team.owner, owner.teamID != team.id else { continue }
            owner.teamID = team.id
            linked += 1
        }
        if linked > 0 { invalidateCache() }
        return linked
    }

    // MARK: - Player-side Resolution

    /// Resolved tiers per club, so the weekly medical pass does not fetch once
    /// per player. Keyed `"<careerID>|<teamID>"` — team ids are only unique
    /// inside a save, and the fixed-league template hands every career the same
    /// deterministic ids, so the career must be part of the key or a second
    /// save slot would read the first one's buildings.
    ///
    /// Every write path (`apply`, `linkOwners`, `processOffseasonInvestment`)
    /// clears it, which is why this cache needs no season or week stamp.
    private static var levelCache: [String: Levels] = [:]

    /// Drops the resolver cache. Called by every mutation in this engine; the
    /// facilities card calls it too after a manual save.
    static func invalidateCache() {
        levelCache = [:]
    }

    /// The tiers a player trains and heals under. Resolves through the
    /// player's club, caches per (career, club), and falls back to neutral for
    /// a free agent, a context-less player, or an owner-less club — so no
    /// caller has to special-case any of those.
    static func levels(forPlayer player: Player) -> Levels {
        guard let teamID = player.teamID else { return .standard }
        let key = "\(player.careerID?.uuidString ?? "-")|\(teamID.uuidString)"
        if let cached = levelCache[key] { return cached }

        guard let context = player.modelContext else { return .standard }
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.id == teamID })
        let owner = (try? context.fetch(descriptor))?.first?.owner
        // Heal the link while we are here: the pinned development lookup needs
        // `Owner.teamID`, and the weekly medical pass walks every rostered
        // player, so the whole league links itself inside one week of play.
        if let owner, owner.teamID != teamID { owner.teamID = teamID }

        let resolved = levels(for: owner)
        levelCache[key] = resolved
        return resolved
    }

    // MARK: - AI Investment

    /// One club's facility decision for the season, for the offseason log.
    struct FacilityDecision {
        let teamID: UUID
        let track: Track
        let fromTier: Int
        let toTier: Int
        /// Owner-voiced one-liner, ready for an offseason feed.
        let summary: String

        var isUpgrade: Bool { toTier > fromTier }
    }

    /// Annual facility pass for the AI clubs: everybody first trims back to
    /// what the owner will actually fund, then spends whatever is left in the
    /// order his persona cares about. Also links every owner to its club.
    ///
    /// The user's club is skipped — the facilities card is the user's lever,
    /// and an AI pass that "helpfully" moved the tiers behind his back would
    /// spend an envelope he was budgeting himself. His owner still gets the
    /// downgrade sweep, because an owner who will not fund the buildings does
    /// not keep paying for them out of goodwill.
    ///
    /// - Parameters:
    ///   - teams: every club in the league.
    ///   - userTeamID: the club the user runs (skipped for upgrades).
    /// - Returns: the tier moves that actually happened.
    @discardableResult
    static func processOffseasonInvestment(teams: [Team], userTeamID: UUID?) -> [FacilityDecision] {
        linkOwners(teams: teams)

        var decisions: [FacilityDecision] = []
        for team in teams {
            guard let owner = team.owner else { continue }
            var current = levels(for: owner)
            let budget = annualBudget(owner: owner)

            // 1. Live within the envelope. Cheapest cut first: the track the
            //    persona ranks last goes down before the one he cares about.
            for track in investmentOrder(for: owner).reversed() {
                while upkeep(levels: current) > budget, current[track] > minTier {
                    let from = current[track]
                    current[track] = from - 1
                    decisions.append(FacilityDecision(
                        teamID: team.id, track: track, fromTier: from, toTier: current[track],
                        summary: "\(team.fullName) let the \(track.displayName.lowercased()) slip to \(tierName(current[track])) — the money wasn't there."
                    ))
                }
            }

            // 2. Spend what is left, best track first. AI clubs move one tier
            //    a year at most so a league takes seasons to stratify.
            if team.id != userTeamID {
                for track in investmentOrder(for: owner) where current[track] < maxTier {
                    var proposed = current
                    proposed[track] = current[track] + 1
                    guard upkeep(levels: proposed) <= budget else { continue }
                    guard Double.random(in: 0..<1) < upgradeAppetite(owner: owner) else { continue }
                    let from = current[track]
                    current = proposed
                    decisions.append(FacilityDecision(
                        teamID: team.id, track: track, fromTier: from, toTier: current[track],
                        summary: "\(team.fullName) broke ground on a \(tierName(current[track]).lowercased()) \(track.displayName.lowercased())."
                    ))
                    break
                }
            }

            apply(current, to: owner)
        }
        invalidateCache()
        return decisions
    }

    /// Which building an owner reaches for first. Follows the personas
    /// `OwnerPersonaEngine` already reads off the same three sliders, so a
    /// Penny Pincher's buildings look like his budget and his patience do.
    static func investmentOrder(for owner: Owner) -> [Track] {
        switch OwnerPersonaEngine.OwnerArchetype.from(owner) {
        case .winNowTycoon:
            // Availability wins games this year; development pays off later.
            return [.medical, .recovery, .training]
        case .patientBuilder:
            // The whole plan is "draft them and grow them".
            return [.training, .recovery, .medical]
        case .pennyPincher:
            // Whatever keeps the roster on the field for the least money.
            return [.medical, .training, .recovery]
        case .meddler:
            // He read an article about sports science and now it is his idea.
            return [.training, .medical, .recovery]
        }
    }

    /// Per-season chance an AI owner who CAN afford the next tier actually
    /// signs off on it. Deliberately low so the league stratifies over many
    /// seasons rather than everybody maxing out by year three.
    static func upgradeAppetite(owner: Owner) -> Double {
        switch OwnerPersonaEngine.OwnerArchetype.from(owner) {
        case .winNowTycoon:   return 0.45
        case .meddler:        return 0.30
        case .patientBuilder: return 0.35
        case .pennyPincher:   return 0.10
        }
    }

    // MARK: - Owner Meeting

    /// The facilities line for the owner meeting: what he thinks of the
    /// buildings he is paying for, and what he expects for it.
    static func ownerMeetingLine(owner: Owner?) -> String {
        guard let owner else {
            return "Nobody has put a number on the facilities this year."
        }
        let levels = levels(for: owner)
        let spend = upkeep(levels: levels)
        let budget = annualBudget(owner: owner)
        let money = "$\(String(format: "%.1f", Double(spend) / 1_000.0))M a year"

        let worst = Track.allCases.min { levels[$0] < levels[$1] } ?? .training
        let best = Track.allCases.max { levels[$0] < levels[$1] } ?? .training

        if levels == .standard {
            let line = "The buildings are league standard across the board — \(money). "
                + "That's what everybody else has, so it buys us nothing and costs us nothing."
            // Tier 2 is neutral by design, so the null sentence is the only true
            // thing to say about the buildings — and on its own it reads as "this
            // system does nothing". The headroom is the affordance: at
            // all-standard the envelope often already covers one track going
            // state-of-the-art, which is the whole decision.
            if budget - spend >= annualCost(tier: maxTier) - annualCost(tier: 2) {
                return line + " There's room in the envelope for one of them to go state-of-the-art — tell me when you want it."
            }
            return line
        }
        if levels[worst] == minTier {
            return "I'm putting \(money) into the buildings and the \(worst.displayName.lowercased()) is still dated. "
                + (spend < budget
                   ? "There's room in the budget for it — tell me when you want it."
                   : "That's what the budget stretches to right now.")
        }
        if levels[best] == maxTier {
            return "The \(best.displayName.lowercased()) is the best in the league and it costs me \(money). "
                + "I expect that to show up in how this roster develops."
        }
        return "Facilities run me \(money) a year. Nothing embarrassing, nothing that wins us a game on its own."
    }

    // MARK: - Display Helpers

    /// Human-readable effect of a track at a given tier, for the facilities
    /// card. Always phrased against league standard.
    static func effectSummary(track: Track, tier: Int) -> String {
        var levels = Levels.standard
        levels[track] = tier
        switch track {
        case .training:
            return percentDelta(developmentMultiplier(levels: levels)) + " development speed"
        case .medical:
            return percentDelta(injuryRiskMultiplier(levels: levels)) + " injury rate"
        case .recovery:
            let weeks = percentDelta(recoveryWeeksMultiplier(levels: levels))
            let bonus = fatigueRecoveryBonus(levels: levels)
            let fatigue = bonus == 0 ? "" : ", \(bonus > 0 ? "+" : "")\(bonus) fatigue/week"
            return weeks + " time on the shelf" + fatigue
        }
    }

    /// `1.06` → `"+6%"`, `0.92` → `"−8%"`, `1.0` → `"no change"`.
    private static func percentDelta(_ multiplier: Double) -> String {
        let pct = Int(((multiplier - 1.0) * 100).rounded())
        if pct == 0 { return "no change to" }
        return pct > 0 ? "+\(pct)%" : "\u{2212}\(abs(pct))%"
    }
}
