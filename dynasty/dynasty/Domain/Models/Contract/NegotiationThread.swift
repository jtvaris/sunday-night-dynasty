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
enum AgentRefusalReason: String, Codable, CaseIterable {
    /// He is not playing. No contract talk survives a healthy scratch.
    case benched
    /// The team loses. He has no interest in signing up for more of it.
    case losingCulture
    /// He has already decided he wants out.
    case wantsOut
    /// Last contract of a career he intends to end on his own terms.
    case ridingIntoRetirement

    /// Short label for the entry-point badge.
    var badgeLabel: String {
        switch self {
        case .benched:              return "Not talking"
        case .losingCulture:        return "Not talking"
        case .wantsOut:             return "Wants out"
        case .ridingIntoRetirement: return "Weighing retirement"
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
    /// calls this and then adds the one door it owns (a mercenary who will not
    /// sign up to lose). The chat layer keeps owning the *wording*. Everything
    /// here reads stance signals (snaps, record, tenure, age), never money.
    static func evaluate(
        playerID: UUID,
        season: Int,
        age: Int,
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

        // Riding into retirement: an old man on a bad team who has already
        // given this building years. Checked first — it outranks every other
        // reason he might have to say no.
        if age >= 35, morale < 80, roll < 45 {
            return .ridingIntoRetirement
        }

        // Benched: snaps are the loudest signal in the building. Only counts
        // once enough of the season has been played for "0 starts" to mean
        // something.
        if weeksPlayed >= 6, gamesStartedThisSeason == 0, morale < 65, roll < 70 {
            return .benched
        }

        // Wants out: unhappy and not tied to the place.
        if morale < 45, loyaltyYears <= 2, roll < 55 {
            return .wantsOut
        }

        // Losing culture: the record speaks, and he is not deaf to it.
        let played = teamWins + teamLosses
        if played >= 8, teamWins * 3 <= played, morale < 60, roll < 40 {
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

    /// Subtitle for a button that also wants to show a money hint: the thread
    /// state wins when there is one, because a live conversation is the more
    /// useful thing to know.
    static func subtitle(for player: Player, season: Int, fallback: String?) -> String? {
        badge(for: player, season: season) ?? fallback
    }
}
