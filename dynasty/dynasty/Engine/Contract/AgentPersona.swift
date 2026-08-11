import Foundation

// MARK: - Agent Persona (R22)

/// Deterministic negotiation persona for a player's agent. Purely derived
/// from the player's UUID (same pattern as `GameWeather.forGame`), so no
/// SwiftData field is needed and every screen shows the same agent for the
/// same player across launches.
///
/// The persona shapes the whole negotiation:
/// - demand level (±10-15% on the opening ask)
/// - patience (how many counter-offer rounds the agent tolerates)
/// - lowball tolerance (a hardliner cuts off talks for the offseason)
enum AgentPersona: String, CaseIterable {

    /// Drives a hard bargain: asks high, walks early, and a lowball offer
    /// ends negotiations for the rest of the offseason.
    case hardliner

    /// Deal-maker: reasonable ask, patient, always keeps talking.
    case cooperative

    /// Values loyalty and fit: modest ask for the home team, but expects
    /// the relationship to be honored.
    case loyalist

    // MARK: - Deterministic Derivation

    /// Deterministic persona draw for one player.
    ///
    /// Distribution: hardliner 30% / cooperative 40% / loyalist 30%.
    /// The roll comes from the UUID's raw bytes (bytes 8-15), NOT `hashValue`
    /// — Hashable's seed changes every launch, which would re-roll the
    /// persona per run.
    static func forPlayer(id: UUID) -> AgentPersona {
        let roll = Int(uuidValue(id, byteOffset: 8) % 100)
        switch roll {
        case ..<30:  return .hardliner
        case ..<70:  return .cooperative
        default:     return .loyalist
        }
    }

    /// Deterministic agent name for one player (stable across launches).
    static func agentName(for id: UUID) -> String {
        let index = Int(uuidValue(id, byteOffset: 0) % UInt64(agentNamePool.count))
        return agentNamePool[index]
    }

    /// A name from the same pool for a surface with no player to key on — the
    /// offseason cold-call in `InboxEngine`, which is an agent talking about
    /// "several clients" rather than about one man.
    ///
    /// This is the ONLY other agent-name source in the app on purpose: the pool
    /// below is the one place a name has to clear the anonymization gate
    /// (`tools/league-data/scan_bundle.py`, check F), and a second literal list
    /// somewhere else is exactly how five real, working NFL agents shipped in
    /// `InboxEngine` unnoticed.
    static func randomAgentName() -> String {
        agentNamePool.randomElement() ?? agentNamePool[0]
    }

    /// Packs 8 UUID bytes (starting at `byteOffset`, wrapping at 16) into a UInt64.
    private static func uuidValue(_ id: UUID, byteOffset: Int) -> UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(bytes[(byteOffset + i) % 16])
        }
        return value
    }

    private static let agentNamePool: [String] = [
        "Marcus Cole", "Dana Whitfield", "Sol Bergman", "Rich Alvarez",
        "Tanya Brooks", "Jerry Feldman", "Andre Simmons", "Kate Donovan",
        "Vince Caruso", "Lamar Ellis", "Priya Nair", "Doug McAllister",
        "Renee Ortiz", "Chad Barker", "Isaiah Grant", "Monica Reyes",
        "Bill Straub", "Terrell Watkins", "Nina Kowalski", "Gary Lipman",
        "Omar Haddad", "Jess Trainor", "Frank DiMarco", "Alicia Vaughn"
    ]

    // MARK: - Display

    /// Short style label shown next to the agent's name in negotiation UI.
    var styleLabel: String {
        switch self {
        case .hardliner:   return "Hard Negotiator"
        case .cooperative: return "Deal-Maker"
        case .loyalist:    return "Loyalty-Driven"
        }
    }

    /// One-line style description for headers/tooltips.
    var styleDescription: String {
        switch self {
        case .hardliner:   return "Asks high, walks early. Lowball at your own risk."
        case .cooperative: return "Wants a deal done. Willing to meet in the middle."
        case .loyalist:    return "Rewards commitment. Discounts for teams that show respect."
        }
    }

    /// SF Symbol for compact persona chips.
    var symbolName: String {
        switch self {
        case .hardliner:   return "flame.fill"
        case .cooperative: return "hand.thumbsup.fill"
        case .loyalist:    return "heart.fill"
        }
    }

    // MARK: - Negotiation Behavior

    /// Multiplier on the agent's opening demand (spec: ±10-15%).
    var demandFactor: Double {
        switch self {
        case .hardliner:   return 1.13
        case .cooperative: return 0.90
        case .loyalist:    return 0.97
        }
    }

    /// How many GM counter-offer rounds the agent tolerates before walking.
    var maxRounds: Int {
        switch self {
        case .hardliner:   return 2
        case .cooperative: return 4
        case .loyalist:    return 3
        }
    }

    /// Offer-to-ask ratio below which the agent considers the offer insulting.
    /// For a hardliner this ends negotiations for the rest of the offseason.
    var lowballCutoff: Double {
        switch self {
        case .hardliner:   return 0.72
        case .cooperative: return 0.55
        case .loyalist:    return 0.62
        }
    }

    /// Whether an insulting offer cuts off talks until next offseason.
    var breaksOffForSeason: Bool {
        self == .hardliner
    }

    /// Extra acceptance-threshold shift used by the quick re-sign flow
    /// (positive = harder to satisfy).
    var reSignThresholdShift: Double {
        switch self {
        case .hardliner:   return 0.08
        case .cooperative: return -0.05
        case .loyalist:    return -0.02
        }
    }

    // MARK: - Voice

    /// The voice this agent speaks in.
    ///
    /// Persona is *behaviour* (how hard he bargains); voice is *character* (how
    /// he says it). They are related but not the same: two deal-makers can be a
    /// polished pro and a backslapping friend of the family, and the difference
    /// is the whole point of putting the negotiation in a chat window.
    ///
    /// A hardliner is always a shark — the behaviour is too distinctive to give
    /// a warm voice to. The other two personas split deterministically on the
    /// player's UUID, so the same man always has the same agent.
    func voice(for id: UUID) -> AgentVoice {
        switch self {
        case .hardliner:
            return .shark
        case .cooperative:
            return AgentVoice.coinFlip(id) ? .professional : .friendly
        case .loyalist:
            return AgentVoice.coinFlip(id) ? .oldSchool : .friendly
        }
    }
}

// MARK: - Agent Voice

/// The four archetypes a contract conversation is written in.
enum AgentVoice: String, CaseIterable {
    /// Transactional, aggressive, allergic to sentiment.
    case shark
    /// Measured, prepared, talks in comparables.
    case professional
    /// Warm, first-name basis, wants everyone to leave happy.
    case friendly
    /// Been doing this thirty years and will tell you so.
    case oldSchool

    /// Short label for the persona chip.
    var label: String {
        switch self {
        case .shark:        return "Shark"
        case .professional: return "Polished Pro"
        case .friendly:     return "Friend of the Family"
        case .oldSchool:    return "Old School"
        }
    }

    /// Deterministic 50/50 split on UUID bytes 12-15 — an offset neither
    /// `AgentPersona.forPlayer` (byte 8) nor `AgentRefusalReason.evaluate`
    /// (byte 4) uses, so voice, persona and stance stay uncorrelated.
    fileprivate static func coinFlip(_ id: UUID) -> Bool {
        let b = id.uuid
        let sum = UInt64(b.12) &+ UInt64(b.13) &+ UInt64(b.14) &+ UInt64(b.15)
        return sum % 2 == 0
    }
}

// MARK: - Agent Dialogue (Contact Agent wave; library split #86)

/// Everything an agent SAYS — the assembly half.
///
/// No evaluation lives here. The chat layer hands this type a tone (what the
/// demand model decided), an ``AgentDesire`` (what the CLIENT is after) and a
/// `Context` of already-formatted strings, and gets back one line in the right
/// voice. That split is the point: the engine never writes UI copy and the copy
/// never invents a number, so a counter reads "We're thinking $54M a year" with
/// the *same* $54M the engine put on the offer card underneath it.
///
/// **The lines themselves live in `AgentDialogueLibrary`.** They moved out when
/// the desire axis went in and the pools went from ~90 sentences to ~470: a file
/// that owns the persona model, the voice model and half a thousand lines of
/// copy is a file nobody edits twice. What is left here is the assembler — which
/// pools a site is made of, in which order, and through which
/// ``DialogueSelector``.
enum AgentDialogue {

    /// Pre-formatted strings a line may interpolate. The chat layer fills this
    /// in from the offers the engine produced; nothing in here is computed.
    struct Context {
        /// "Justin"
        var playerFirst: String
        /// "Justin Jefferson"
        var playerFull: String
        /// "WR"
        var position: String
        /// The club, as a NOUN PHRASE — "the Harbormen", or "this club" when the
        /// conversation has no team to name (a true free agent).
        ///
        /// A noun phrase rather than a bare nickname on purpose: the fallback
        /// has to read as English in the same sentence the real value does, so
        /// every line that uses it says "with \(ctx.team)" and never
        /// "a \(ctx.team) man" — which would come out as "a this club man" the
        /// moment the player has no team row.
        var team: String
        /// The ask, per year — "$54.0M".
        var askPerYear: String
        /// Total value of the ask — "$216.0M".
        var askTotal: String
        /// Years on the ask.
        var askYears: Int
        /// What the GM just put on the table, per year — "$41.5M".
        var offerPerYear: String
        /// The deal that was actually signed, per year.
        var signedPerYear: String
        var signedTotal: String
        var signedYears: Int
        /// How many rounds it took to get there.
        var rounds: Int

        init(
            playerFirst: String = "",
            playerFull: String = "",
            position: String = "",
            team: String = "this club",
            askPerYear: String = "",
            askTotal: String = "",
            askYears: Int = 0,
            offerPerYear: String = "",
            signedPerYear: String = "",
            signedTotal: String = "",
            signedYears: Int = 0,
            rounds: Int = 0
        ) {
            self.playerFirst = playerFirst
            self.playerFull = playerFull
            self.position = position
            self.team = team
            self.askPerYear = askPerYear
            self.askTotal = askTotal
            self.askYears = askYears
            self.offerPerYear = offerPerYear
            self.signedPerYear = signedPerYear
            self.signedTotal = signedTotal
            self.signedYears = signedYears
            self.rounds = rounds
        }
    }

    // MARK: - Assembly
    //
    // Every function below is a THIN assembler: it picks parts out of
    // `AgentDialogueLibrary` through a `DialogueSelector` and joins them with a
    // space. No branching on money, no grading, no eligibility — the tone and
    // the desire are both handed in, already decided.

    /// The first thing the agent says when the GM picks up the phone: hello,
    /// what his client is actually after, and the number it will take.
    static func opener(
        voice: AgentVoice,
        desire: AgentDesire,
        isExtension: Bool,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        let greeting = sel.pick(
            .openGreeting, key: isExtension ? "ext" : "fa",
            from: AgentDialogueLibrary.openGreeting(voice: voice, isExtension: isExtension)
        )
        return [greeting, desireAndNumber(voice: voice, desire: desire, ctx: ctx, sel: sel)]
            .joined(separator: " ")
    }

    /// The same opener said a second time, after a refusing client changed his
    /// mind. Deliberately shares the desire and number pools with ``opener`` —
    /// a reopen IS an opening, and what the man wants did not change while the
    /// door was shut.
    static func reopener(
        voice: AgentVoice,
        desire: AgentDesire,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        let greeting = sel.pick(
            .reopenGreeting,
            from: AgentDialogueLibrary.reopenGreeting(voice: voice, ctx: ctx)
        )
        return [greeting, desireAndNumber(voice: voice, desire: desire, ctx: ctx, sel: sel)]
            .joined(separator: " ")
    }

    private static func desireAndNumber(
        voice: AgentVoice, desire: AgentDesire, ctx: Context, sel: DialogueSelector
    ) -> String {
        let want = sel.pick(
            .openDesire, key: desire.rawValue,
            from: AgentDialogueLibrary.openDesire(voice: voice, desire: desire, ctx: ctx)
        )
        let hint = sel.pick(
            .openHint, from: AgentDialogueLibrary.openHint(voice: voice, ctx: ctx)
        )
        return [want, hint].joined(separator: " ")
    }

    /// What a client who just won a prove-it bet opens with. No desire weave:
    /// the bet IS the thing he wants said, and the line already says it.
    static func provenBetLine(voice: AgentVoice, ctx: Context, sel: DialogueSelector) -> String {
        sel.pick(.provenBet, from: AgentDialogueLibrary.provenBet(voice: voice, ctx: ctx))
    }

    // MARK: Refusal

    /// The client will not come to the table — in character, with the reason
    /// showing. Three parts: the refusal, why, and how this agent signs off.
    static func refusalLine(
        voice: AgentVoice,
        reason: AgentRefusalReason,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        let core = sel.pick(.refuseCore, from: AgentDialogueLibrary.refuseCore(voice: voice, ctx: ctx))
        let flavor = sel.pick(
            .refuseFlavor, key: reason.rawValue,
            from: AgentDialogueLibrary.refuseFlavor(voice: voice, reason: reason, ctx: ctx)
        )
        let sign = sel.pick(.refuseSign, from: AgentDialogueLibrary.refuseSign(voice: voice))
        return [core, flavor, sign].joined(separator: " ")
    }

    // MARK: Pestering

    /// **The answer to an offer tabled at a man who already said no.**
    ///
    /// Escalates by tier and never softens — the pools are per-tier for exactly
    /// that reason. `attempt` is 1-based.
    static func pesteringLine(
        voice: AgentVoice,
        reason: AgentRefusalReason,
        attempt: Int,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        if attempt <= 1, reason.neverSignsAtAnyPrice {
            return sel.pick(.pester, key: "never",
                            from: AgentDialogueLibrary.neverSigns(voice: voice, ctx: ctx))
        }
        let tier = max(1, min(3, attempt))
        return sel.pick(.pester, key: "t\(tier)",
                        from: AgentDialogueLibrary.pestering(voice: voice, tier: tier, ctx: ctx))
    }

    // MARK: Counters

    /// A counter-offer, spoken: what his client wants, and the number that wants
    /// it. `ctx.askPerYear` is the engine's counter for THIS round, not the
    /// opener, so the sentence and the card underneath it agree.
    ///
    /// The insulted frame puts the number first — an insult is a reaction to a
    /// figure, and burying it behind a sentence about the client's ambitions
    /// reads as a non-sequitur.
    static func counterLine(
        voice: AgentVoice,
        desire: AgentDesire,
        tone: AgentToneKey,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        let body = sel.pick(
            .counterBody, key: desire.rawValue,
            from: AgentDialogueLibrary.counterBody(voice: voice, desire: desire, ctx: ctx)
        )
        let number = sel.pick(
            .counterNumber, key: tone.rawValue,
            from: AgentDialogueLibrary.counterNumber(voice: voice, tone: tone, ctx: ctx)
        )
        return tone == .insulted
            ? [number, body].joined(separator: " ")
            : [body, number].joined(separator: " ")
    }

    // MARK: Years pushback

    /// The agent will not sign his man to a deal longer than his body has left.
    static func yearsPushbackLine(
        voice: AgentVoice,
        age: Int,
        requestedYears: Int,
        maxYears: Int,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        sel.pick(.yearsPushback, from: AgentDialogueLibrary.yearsPushback(
            voice: voice, age: age, requestedYears: requestedYears,
            maxYears: maxYears, ctx: ctx
        ))
    }

    // MARK: Close

    /// Acceptance, in the tone of the JOURNEY — the deal being good is not the
    /// same as the negotiation having been good — and in terms of what the man
    /// was after, so the signature says whether he got it.
    static func acceptLine(
        voice: AgentVoice,
        desire: AgentDesire,
        tone: AgentToneKey,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        let isGrudging = !(tone == .eager || tone == .professional)
        let number = sel.pick(
            .acceptNumber, key: isGrudging ? "grudge" : tone.rawValue,
            from: AgentDialogueLibrary.acceptNumber(voice: voice, tone: tone, ctx: ctx)
        )
        let body = sel.pick(
            .acceptBody, key: "\(desire.rawValue).\(isGrudging)",
            from: AgentDialogueLibrary.acceptBody(
                voice: voice, desire: desire, isGrudging: isGrudging, ctx: ctx
            )
        )
        return [number, body].joined(separator: " ")
    }

    /// The note a begrudging close leaves on the player — named in terms of what
    /// he wanted, because that is the thing the roster row has to keep teaching.
    static func lingeringNote(desire: AgentDesire, ctx: Context, sel: DialogueSelector) -> String {
        sel.pick(.lingering, key: desire.rawValue,
                 from: AgentDialogueLibrary.lingering(desire: desire, ctx: ctx))
    }

    // MARK: Endings

    static func walkAwayLine(
        voice: AgentVoice, ctx: Context, sel: DialogueSelector
    ) -> String {
        sel.pick(.walkAway, from: AgentDialogueLibrary.walkAway(voice: voice, ctx: ctx))
    }

    static func brokenOffLine(voice: AgentVoice, ctx: Context, sel: DialogueSelector) -> String {
        sel.pick(.brokenOff, from: AgentDialogueLibrary.brokenOff(voice: voice, ctx: ctx))
    }

    /// What the front office says when it puts an offer on the table.
    static func gmOfferLine(round: Int, playerFirst: String, sel: DialogueSelector) -> String {
        sel.pick(.gmOffer, key: round <= 1 ? "open" : "again",
                 from: AgentDialogueLibrary.gmOffer(round: round, playerFirst: playerFirst))
    }

    // MARK: Pay cut (#102)

    /// The front office asking for money back. `ctx.offerPerYear` is the number
    /// the composer currently has, so the sentence and the ask card agree.
    static func payCutAskLine(playerFirst: String, ctx: Context, sel: DialogueSelector) -> String {
        sel.pick(.payCutAsk, from: AgentDialogueLibrary.payCutAsk(playerFirst: playerFirst, ctx: ctx))
    }

    /// The agent's answer to a pay-cut ask.
    ///
    /// One entry point per verdict rather than a tone switch, because the four
    /// answers are four different SPEECH ACTS — a counter names a number, a
    /// release demand names a transaction — and folding them into one pool by
    /// tone is how a "no" ends up quoting a figure it never offered.
    ///
    /// `ctx.askPerYear` carries the agent's counter where there is one, matching
    /// every other counter site in this file.
    static func payCutAnswerLine(
        voice: AgentVoice,
        outcome: ContractNegotiationEngine.PayCutOutcome,
        ctx: Context,
        sel: DialogueSelector
    ) -> String {
        switch outcome {
        case .accepted:
            return sel.pick(.payCutAccept, from: AgentDialogueLibrary.payCutAccept(voice: voice, ctx: ctx))
        case .countered:
            return sel.pick(.payCutCounter, from: AgentDialogueLibrary.payCutCounter(voice: voice, ctx: ctx))
        case .refused:
            return sel.pick(.payCutRefuse, from: AgentDialogueLibrary.payCutRefuse(voice: voice, ctx: ctx))
        case .demandsRelease:
            return sel.pick(.payCutRelease, from: AgentDialogueLibrary.payCutRelease(voice: voice, ctx: ctx))
        }
    }
}

// MARK: - Negotiation Lock Registry (R22)

/// Tracks players whose agents have cut off contract talks for the current
/// offseason (hardliner insulted by a lowball). UserDefaults-backed —
/// intentionally lightweight; cleared when a new season kicks off in
/// `WeekAdvancer.startNewSeason`.
enum NegotiationLockRegistry {

    /// Base key — namespaced per save through `CareerScopedDefaults.scopedKey`.
    /// The bare key is never touched: `migrateGlobalKeys` moves the legacy value
    /// to the scoped one and deletes the global, so a registry still reading the
    /// bare key would report "nobody is locked" for every save after the update.
    private static let baseKey = "negotiationLockedPlayerIDs"

    private static var key: String { CareerScopedDefaults.scopedKey(baseKey) }

    /// Marks a player's agent as refusing further talks this offseason.
    static func lock(_ playerID: UUID) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        ids.insert(playerID.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// Whether the player's agent refuses to negotiate right now.
    static func isLocked(_ playerID: UUID) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        return ids.contains(playerID.uuidString)
    }

    /// Clears every lock — called when a new season starts.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
