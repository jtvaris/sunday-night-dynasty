import Foundation

// MARK: - Negotiation Thread (Contact Agent wave)
//
// The persisted state of ONE conversation with ONE player's agent.
//
// WHY a thread and not a throwaway sheet: before this wave a contract talk
// existed only while `ContractNegotiationView` was on screen. Close it and the
// transcript, the round count and the agent's standing counter were gone — and
// because the sheet dismissed itself the instant a deal was struck, the user
// never even read the line the agent said when he signed. Worse, the entry
// button leaked the answer: "Extend Contract" appeared only where an extension
// was possible, so the roster told you who would talk before you picked up the
// phone.
//
// This is the `TradeNegotiationThread` template (Domain/Models/League) applied
// to contracts: a transcript of `NegotiationThreadMessage` bubbles, offer
// snapshots frozen at the moment each line was said, a status that survives the
// view, and a close tone that outlives the conversation because it is what the
// morale write is keyed on.
//
// PERSISTENCE: careerID-scoped `UserDefaults` through `NegotiationThreadStore`,
// exactly like `ContractIncentiveRegistry` and `NegotiationLockRegistry`. The
// blob is small (a few dozen threads of a few lines each), it is written by hand
// a handful of times per offseason, and keeping it out of `Career` means this
// wave adds no SwiftData migration.

// MARK: - Agent Tone

/// The voice an agent line is spoken in.
///
/// **Ownership note.** The *demand model* (what the agent asks for, what his
/// floor is, and which of these tones the money justifies) belongs to
/// `ContractNegotiationEngine`. This enum is the chat layer's persistence and
/// dialogue key for the tone it is handed — `NegotiationThreadMessage` stores
/// the raw string so a transcript written months ago still renders in the voice
/// it was said in, even if the tone vocabulary grows.
///
/// Raw-string backed for the same migration-safety reason
/// `TradeRecord.phaseRaw` is.
enum AgentToneKey: String, Codable, CaseIterable {
    /// Wants the deal done — the number is close and he says so.
    case eager
    /// Business as usual. States the ask, states the gap.
    case professional
    /// Dug in. The ask does not move much and the patience is visibly shorter.
    case hardline
    /// The offer was an insult. He says it out loud.
    case insulted
    /// Will not negotiate at all right now, for a reason he will give you.
    case refusing

    /// Whether a line in this tone means the conversation is over before it
    /// started.
    var isRefusal: Bool { self == .refusing }
}

// MARK: - Refusal Reason

/// Why a client has no interest in talking to this team right now.
///
/// Stance, not money: an agent refuses because of what the building has done to
/// his man, not because of a number. Each case has its own flavor line in
/// `AgentDialogue.refusalLine`.
///
/// **The reason decides what money cannot fix.** Four of these are moods with a
/// price attached somewhere down the line — start him, win a few, let the winter
/// pass — and they lift on their own as the inputs move. ``ringChasing`` is the
/// one that is not a mood at all: an elite competitor on a club that is going
/// nowhere does not want a bigger number, he wants a different season, and no
/// offer this front office can write is the thing he is asking for. See
/// ``neverSignsAtAnyPrice`` and ``exitCondition``.
enum AgentRefusalReason: String, Codable, CaseIterable {
    /// He is not playing. No contract talk survives a healthy scratch.
    case benched
    /// The team loses. He has no interest in signing up for more of it.
    case losingCulture
    /// He has already decided he wants out.
    case wantsOut
    /// Last contract of a career he intends to end on his own terms.
    case ridingIntoRetirement
    /// **Never-sign.** Elite, fiercely competitive, and out of patience with a
    /// club that is going nowhere. He is not holding out for more money — he is
    /// holding out for a contender, and the only thing that reopens the door is
    /// the record. Deliberately rare: see
    /// `ContractNegotiationEngine.ringChaserVerdict` for the eligibility gates
    /// that hold it to a handful of men league-wide per season.
    case ringChasing

    /// Short label for the entry-point badge.
    var badgeLabel: String {
        switch self {
        case .benched:              return "Not talking"
        case .losingCulture:        return "Not talking"
        case .wantsOut:             return "Wants out"
        case .ridingIntoRetirement: return "Weighing retirement"
        case .ringChasing:          return "Wants a winner"
        }
    }

    /// Whether money is simply the wrong instrument here.
    ///
    /// Load-bearing rather than decorative: the pestering path reads it to
    /// decide whether an offer is a bad idea (the other four — he may come round
    /// next league year) or a category error (this one — he never will, at any
    /// number, until the standings change).
    var neverSignsAtAnyPrice: Bool { self == .ringChasing }

    /// The single sentence that says what WOULD change his mind, shown next to
    /// the refusal so the stance is a puzzle rather than a wall.
    var exitCondition: String {
        switch self {
        case .benched:
            return "Play him. Snaps reopen this conversation; money does not."
        case .losingCulture:
            return "Win games. He is listening to the record, not the offer."
        case .wantsOut:
            return "Mend it or move him — he has already made his decision about the room."
        case .ridingIntoRetirement:
            return "Give him the winter. He may feel differently about football next league year."
        case .ringChasing:
            return "Become a contender. No price signs him while this club is going nowhere."
        }
    }

    // MARK: Derivation

    /// Whether this player's camp refuses to open contract talks, and why.
    ///
    /// Deterministic per player AND per league year (UUID-seeded, the
    /// `AgentPersona.forPlayer` pattern, salted by `season`) so reopening a
    /// thread never re-rolls the stance inside the season it belongs to, and so
    /// a refusal that shows in the badge is the refusal the chat states.
    ///
    /// **Why `season` is not optional.** Without it the roll is fixed for the
    /// life of the save, and because every other input here is monotone in the
    /// wrong direction (age only rises), a 35-year-old who once drew
    /// `.ridingIntoRetirement` refused *every league year for the rest of his
    /// career* with no lever the player could pull except morale ≥ 80. A stance
    /// is a mood about a moment; it has to be allowed to change.
    ///
    /// The verdict belongs to `ContractNegotiationEngine.refusalVerdict`, which
    /// calls this and then adds the two doors it owns (the ring-chaser, and a
    /// mercenary who will not sign up to lose). The chat layer keeps owning the
    /// *wording*. Everything here reads stance signals (snaps, record, tenure,
    /// age), never money.
    ///
    /// ## The rarity budget
    ///
    /// **The mass of negotiations must go normally.** A refusal is a story beat,
    /// and a story beat that fires on a fifth of the roster is a mechanic the
    /// user routes around rather than reacts to. The budget this model is
    /// written to is `< 5 %` of re-sign candidates refusing for ANY reason,
    /// which is why every rule below is gated **structurally** first and only
    /// then by a roll:
    ///
    /// | reason | structural gate | roll | ≈ share of candidates |
    /// |---|---|---|---|
    /// | retirement | 35+, morale < 70 | 25 % | ~0.2 % |
    /// | benched | 72+ OVR, 0 starts by week 6, morale < 60 | 30 % | ~0.6 % |
    /// | wants out | morale < 40, ≤ 2 years here | 35 % | ~0.8 % |
    /// | losing culture | ≤ .333 ball through 8 games, morale < 55 | 25 % | ~1.3 % |
    ///
    /// The structural half is what makes the budget hold as a league ages: rolls
    /// alone would scale with roster size, while "an above-replacement man who
    /// has not started a game by week six AND is unhappy about it" stays a small
    /// and self-limiting population however many players exist.
    ///
    /// The `overall` gate on `.benched` is the single biggest change from the
    /// first cut of this model, and it is worth naming: without it, *every
    /// backup on the roster* — thirty men per club, most of whom have never
    /// started a game in their lives and are not remotely insulted by that —
    /// was rolling for a refusal, which put the real figure north of 10 %.
    /// A healthy scratch is only an insult to somebody who should be playing.
    static func evaluate(
        playerID: UUID,
        season: Int,
        age: Int,
        overall: Int,
        morale: Int,
        gamesStartedThisSeason: Int,
        loyaltyYears: Int,
        teamWins: Int,
        teamLosses: Int,
        weeksPlayed: Int
    ) -> AgentRefusalReason? {
        // A deterministic 0-99 roll, from bytes the persona draw does not use,
        // mixed with the league year so the stance is stable inside a season and
        // re-drawn at the next one.
        let seasonSalt = UInt64(bitPattern: Int64(season)) &* 0x9E37_79B9_7F4A_7C15
        let roll = Int((seed(playerID, byteOffset: 4) ^ seasonSalt) % 100)

        // Riding into retirement: an old man who has already given the game
        // everything he has. Checked first — it outranks every other reason he
        // might have to say no.
        if age >= 35, morale < 70, roll < 25 {
            return .ridingIntoRetirement
        }

        // Benched: snaps are the loudest signal in the building — but only to a
        // man the building should be playing. Below 72 he is a backup, and a
        // backup's agent does not open a contract call by complaining about
        // snaps he was never promised.
        if weeksPlayed >= 6, gamesStartedThisSeason == 0, overall >= 72,
           morale < 60, roll < 30 {
            return .benched
        }

        // Wants out: genuinely unhappy and not tied to the place.
        if morale < 40, loyaltyYears <= 2, roll < 35 {
            return .wantsOut
        }

        // Losing culture: the record speaks, and he is not deaf to it.
        let played = teamWins + teamLosses
        if played >= 8, teamWins * 3 <= played, morale < 55, roll < 25 {
            return .losingCulture
        }

        return nil
    }

    /// Packs 8 UUID bytes into a UInt64 — same helper shape as
    /// `AgentPersona.uuidValue`, kept private here so the two draws cannot
    /// accidentally share an offset and correlate.
    private static func seed(_ id: UUID, byteOffset: Int) -> UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(bytes[(byteOffset + i) % 16])
        }
        return value
    }
}

// MARK: - Offer Snapshot

/// A `NegotiationOffer` frozen into the transcript.
///
/// `NegotiationOffer` itself is a live value type with an identity that changes
/// per instance, so it is not the thing to persist. Storing a snapshot rather
/// than re-deriving today's numbers is the whole point of a transcript: a bubble
/// that re-renders the current ask next to last week's sentence is a lie.
struct NegotiationOfferSnapshot: Codable, Equatable {
    var years: Int
    var annualSalary: Int
    var signingBonus: Int
    var guaranteedPercent: Int
    var noTradeClause: Bool
    var incentives: [ContractIncentive]

    init(_ offer: NegotiationOffer) {
        self.years = offer.years
        self.annualSalary = offer.annualSalary
        self.signingBonus = offer.signingBonus
        self.guaranteedPercent = offer.guaranteedPercent
        self.noTradeClause = offer.noTradeClause
        self.incentives = offer.incentives
    }

    /// Back to the live type the engine and the offer card both speak.
    var offer: NegotiationOffer {
        NegotiationOffer(
            years: years,
            annualSalary: annualSalary,
            signingBonus: signingBonus,
            guaranteedPercent: guaranteedPercent,
            noTradeClause: noTradeClause,
            incentives: incentives
        )
    }
}

// MARK: - Message

enum NegotiationThreadSender: String, Codable {
    /// The player's agent.
    case agent
    /// The user's front office.
    case you
    /// Neutral narration — the signed card, "you walked away".
    case system
}

/// One bubble in a contract transcript.
struct NegotiationThreadMessage: Codable, Identifiable {
    let id: UUID
    let sender: NegotiationThreadSender
    let text: String
    /// The deal as it stood when this line was said.
    let offer: NegotiationOfferSnapshot?
    /// Negotiation round this line belongs to (0 = the agent's opener).
    let round: Int
    /// The tone an agent line was spoken in. `nil` on user and system lines.
    let toneRaw: String?
    /// True for the inline signed-confirmation card, which renders as a receipt
    /// rather than as speech.
    let isSignedCard: Bool

    var tone: AgentToneKey? { toneRaw.flatMap(AgentToneKey.init(rawValue:)) }

    init(
        id: UUID = UUID(),
        sender: NegotiationThreadSender,
        text: String,
        offer: NegotiationOfferSnapshot? = nil,
        round: Int,
        tone: AgentToneKey? = nil,
        isSignedCard: Bool = false
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.offer = offer
        self.round = round
        self.toneRaw = tone?.rawValue
        self.isSignedCard = isSignedCard
    }
}

// MARK: - Status

enum NegotiationThreadStatus: String, Codable {
    /// Talks are live — the composer is open.
    case open
    /// A deal was signed.
    case signed
    /// The user walked.
    case walkedAway
    /// The agent walked (patience spent, or the gap never closed).
    case playerWalked
    /// A lowball killed talks for the offseason (`NegotiationLockRegistry`).
    case brokenOff
    /// The client would not come to the table at all.
    case refused

    var isTerminal: Bool { self != .open }

    /// Whether the composer stays live in this state.
    ///
    /// **A refusal is not a closed door, it is an answer you did not like.** The
    /// club can always table another offer — that is what a front office DOES,
    /// and a screen that takes the composer away is telling the user a rule the
    /// league does not have. What it costs to keep asking is the agent's problem
    /// to state and `ContractNegotiationEngine`'s to price (the ask ratchets, the
    /// man's morale slips, the ledger remembers); it is not the UI's to prevent.
    ///
    /// `.brokenOff` is deliberately NOT here: that one is the agent hanging up
    /// on a lowball for the offseason, which is a consequence the user earned
    /// rather than a stance he can keep pushing against.
    var acceptsOffers: Bool { self == .open || self == .refused }

    /// What the entry button badges when a thread is in this state.
    var entryBadge: String? {
        switch self {
        case .open:        return "Talks ongoing"
        case .signed:      return "Signed"
        case .walkedAway:  return "Talks ended"
        case .playerWalked: return "Talks ended"
        case .brokenOff:   return "Refusing calls"
        case .refused:     return "Not talking"
        }
    }
}

// MARK: - Thread

/// One live conversation with one agent, persisted per save so it survives the
/// sheet, the app launch and the week advance.
struct NegotiationThread: Codable, Identifiable {
    let id: UUID
    let playerID: UUID
    /// Denormalised so a thread list can render without a store fetch.
    let playerName: String
    let agentName: String
    /// `AgentPersona.rawValue` at the time the thread opened.
    let personaRaw: String
    /// `"extend"` / `"freeAgent"` — `NegotiationType` is not `Codable` and lives
    /// in the engine, so the thread stores the discriminator itself.
    let typeRaw: String
    /// The league year the thread belongs to. A thread never crosses a season:
    /// re-contact next window opens a fresh one.
    let season: Int

    /// Completed GM offer rounds, compared against `ContractDemand.maxRounds`
    /// for the patience meter.
    var round: Int
    /// Lowballs this conversation has absorbed.
    ///
    /// Persisted because the demand model is a pure function: recomputing it
    /// each round from the player alone resets the count to zero, so the
    /// documented "each insult costs a round of patience" never fired. Optional
    /// so a transcript written before this field existed still decodes.
    var insultCount: Int?
    /// Offers tabled at a client who had already declined to negotiate.
    ///
    /// Separate from ``insultCount`` because they are different sins with
    /// different tells: an insult is a number that was too low, a pester is a
    /// number offered to a man who said the number was not the problem. The
    /// agent's answer escalates on this count, and it is what the morale write
    /// is metered by. Optional so transcripts written before this field decode.
    var pesterCount: Int?
    var messages: [NegotiationThreadMessage]
    /// The agent's standing counter — what "Accept" accepts.
    var pendingAgentOffer: NegotiationOfferSnapshot?
    /// The opening ask, kept for the whole thread so the close tone can be
    /// judged against what he originally wanted.
    var openingAsk: NegotiationOfferSnapshot?
    var statusRaw: String
    /// Why the client would not talk (only on `.refused`).
    var refusalReasonRaw: String?
    /// The tone the deal actually closed in — what the morale write is keyed on.
    var closeToneRaw: String?
    /// A begrudging signing leaves this behind: the line the roster keeps
    /// showing until something changes.
    var lingeringNote: String?
    /// True once the close has been written to morale/motivation. Guards against
    /// a reopened thread paying out twice.
    var moraleApplied: Bool

    var status: NegotiationThreadStatus {
        get { NegotiationThreadStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var persona: AgentPersona { AgentPersona(rawValue: personaRaw) ?? .cooperative }
    var refusalReason: AgentRefusalReason? { refusalReasonRaw.flatMap(AgentRefusalReason.init(rawValue:)) }
    var closeTone: AgentToneKey? { closeToneRaw.flatMap(AgentToneKey.init(rawValue:)) }

    var isOpen: Bool { status == .open }

    init(
        id: UUID = UUID(),
        playerID: UUID,
        playerName: String,
        agentName: String,
        persona: AgentPersona,
        typeRaw: String,
        season: Int,
        round: Int = 0,
        insultCount: Int = 0,
        pesterCount: Int = 0,
        messages: [NegotiationThreadMessage] = [],
        pendingAgentOffer: NegotiationOfferSnapshot? = nil,
        openingAsk: NegotiationOfferSnapshot? = nil,
        status: NegotiationThreadStatus = .open,
        refusalReason: AgentRefusalReason? = nil,
        closeTone: AgentToneKey? = nil,
        lingeringNote: String? = nil,
        moraleApplied: Bool = false
    ) {
        self.id = id
        self.playerID = playerID
        self.playerName = playerName
        self.agentName = agentName
        self.personaRaw = persona.rawValue
        self.typeRaw = typeRaw
        self.season = season
        self.round = round
        self.insultCount = insultCount
        self.pesterCount = pesterCount
        self.messages = messages
        self.pendingAgentOffer = pendingAgentOffer
        self.openingAsk = openingAsk
        self.statusRaw = status.rawValue
        self.refusalReasonRaw = refusalReason?.rawValue
        self.closeToneRaw = closeTone?.rawValue
        self.lingeringNote = lingeringNote
        self.moraleApplied = moraleApplied
    }

    mutating func append(_ message: NegotiationThreadMessage) {
        messages.append(message)
    }
}

// MARK: - Store

/// careerID-scoped persistence for contract threads.
///
/// Same shape as `ContractIncentiveRegistry`: one JSON blob per save keyed by
/// `player.id.uuidString`, listed in `CareerScopedDefaults.keys` so deleting a
/// save takes its transcripts with it.
enum NegotiationThreadStore {

    /// Base key — namespaced per save through `CareerScopedDefaults.key`.
    static let defaultsKey = "contractNegotiationThreads"

    // MARK: Reads

    /// This player's thread, if one exists in this save.
    static func thread(for player: Player) -> NegotiationThread? {
        guard let careerID = player.careerID else { return nil }
        return map(careerID: careerID)[player.id.uuidString]
    }

    /// The thread only if it belongs to the season being played. A conversation
    /// does not carry across a league year — "re-contact allowed next window"
    /// means a clean sheet, not a reopened argument.
    static func liveThread(for player: Player, season: Int) -> NegotiationThread? {
        guard let thread = thread(for: player), thread.season == season else { return nil }
        return thread
    }

    /// Every thread in one save, keyed by `player.id.uuidString`.
    static func allThreads(careerID: UUID) -> [String: NegotiationThread] {
        map(careerID: careerID)
    }

    // MARK: Writes

    static func upsert(_ thread: NegotiationThread, careerID: UUID) {
        var table = map(careerID: careerID)
        table[thread.playerID.uuidString] = thread
        write(table, careerID: careerID)
    }

    static func remove(playerID: UUID, careerID: UUID) {
        var table = map(careerID: careerID)
        table.removeValue(forKey: playerID.uuidString)
        write(table, careerID: careerID)
    }

    /// Drops every thread in one save (paired with `CareerScopedDefaults.purge`).
    static func purge(careerID: UUID) {
        UserDefaults.standard.removeObject(
            forKey: CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        )
    }

    // MARK: Storage

    private static func map(careerID: UUID) -> [String: NegotiationThread] {
        let key = CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let table = try? JSONDecoder().decode([String: NegotiationThread].self, from: data) else {
            return [:]
        }
        return table
    }

    private static func write(_ table: [String: NegotiationThread], careerID: UUID) {
        let key = CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        guard let data = try? JSONEncoder().encode(table) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Contact Agent Entry

/// The ONE entry point into a contract conversation, shared by every surface
/// that can start one.
///
/// The rule this type exists to enforce: **the button never reveals
/// willingness.** Every player on the roster can be contacted — whether his camp
/// picks up is something the agent says in the chat, in character, not something
/// the roster leaks by hiding a button. Before this wave "Extend Contract"
/// appeared only where an extension was on, which told the user the answer
/// before he asked the question.
enum ContactAgentEntry {

    static let title = "Contact Agent"
    static let icon = "bubble.left.and.bubble.right.fill"

    /// The badge the button carries, if the conversation has a state worth
    /// showing. `nil` when there is nothing to say — which is the default, and
    /// deliberately gives away nothing.
    static func badge(for player: Player, season: Int) -> String? {
        guard let thread = NegotiationThreadStore.liveThread(for: player, season: season) else {
            return nil
        }
        return thread.status.entryBadge
    }

    /// The "wants more" note a begrudging signing left behind, if any.
    static func lingeringNote(for player: Player, season: Int) -> String? {
        NegotiationThreadStore.liveThread(for: player, season: season)?.lingeringNote
    }

    /// What would change a refusing client's mind, for a surface that wants to
    /// show the puzzle rather than only the wall. `nil` unless this player's
    /// live thread is a refusal.
    static func exitCondition(for player: Player, season: Int) -> String? {
        NegotiationThreadStore.liveThread(for: player, season: season)?
            .refusalReason?.exitCondition
    }

    /// Subtitle for a button that also wants to show a money hint: the thread
    /// state wins when there is one, because a live conversation is the more
    /// useful thing to know.
    static func subtitle(for player: Player, season: Int, fallback: String?) -> String? {
        badge(for: player, season: season) ?? fallback
    }
}
