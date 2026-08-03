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

// MARK: - Agent Dialogue (Contact Agent wave)

/// Everything an agent SAYS.
///
/// Line pools only — no evaluation lives here. The chat layer hands this type a
/// tone (what the demand model decided) plus a `Context` of already-formatted
/// strings, and gets back one line in the right voice. That split is the point:
/// the engine never writes UI copy and the copy never invents a number, so a
/// counter reads "We're thinking $54M a year" with the *same* $54M the engine
/// put on the offer card underneath it.
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

    // MARK: Opener

    /// The first thing the agent says when the GM picks up the phone — stance
    /// in character, plus a hint at what it will take.
    static func opener(voice: AgentVoice, isExtension: Bool, ctx: Context) -> String {
        let stance: [String]
        switch voice {
        case .shark:
            stance = isExtension
                ? ["Let's not waste each other's afternoon. \(ctx.playerFirst) is the best \(ctx.position) you have and he gets paid like it.",
                   "You called, so you already know the number is going to hurt. \(ctx.playerFirst) is not signing a discount.",
                   "I'll be direct. \(ctx.playerFirst) has a market, and your building is one bidder in it."]
                : ["\(ctx.playerFirst) has three teams on the phone today. You're the fourth. Make it worth answering.",
                   "Let's be quick about this. Free agency is a seller's market and my client is the product.",
                   "I'll tell you what I told everyone else: the number is the number."]
        case .professional:
            stance = isExtension
                ? ["Thanks for reaching out. \(ctx.playerFirst) is happy here — we'd like to get an extension done before this becomes a story.",
                   "Good to hear from you. We've done our homework on the market, and we think there's a deal here.",
                   "Appreciate the call. \(ctx.playerFirst) wants clarity, and so do we. Let's work."]
                : ["Thanks for the interest. \(ctx.playerFirst) is taking every meeting, and yours is a real one.",
                   "Good to talk. We're evaluating fit and money in that order — but the money still has to be right.",
                   "Appreciate you calling early. That counts for something with us."]
        case .friendly:
            stance = isExtension
                ? ["Hey — great to hear from you. \(ctx.playerFirst) loves it in that building. Let's find a number that keeps him there.",
                   "Glad you called. His wife has the kids in school there. Nobody wants to move. Let's make this easy.",
                   "You know how much he thinks of your locker room. Let's do this the friendly way."]
                : ["Hey! \(ctx.playerFirst) had a great visit. He liked the place, he liked the people.",
                   "Thanks for calling. He's excited about the fit — we just need the deal to make sense.",
                   "Great to talk to you. He's got options, but he keeps coming back to your name."]
        case .oldSchool:
            stance = isExtension
                ? ["I've been doing this a long time, and \(ctx.playerFirst) is the kind of man you keep. Let's keep him.",
                   "In my day you paid your own before somebody else did. That's still the advice I give.",
                   "\(ctx.playerFirst) has bled for that building. We're not here to squeeze you — we're here to be right."]
                : ["I'll say what I always say: money matters, but so does where a man plays out his best years.",
                   "He's had a career worth respecting. Whoever signs him ought to act like it.",
                   "Let's talk plainly. What's the shape of the deal you have in mind?"]
        }
        return "\(stance.randomElement()!) \(expectationHint(voice: voice, ctx: ctx))"
    }

    /// The "here's what it takes" half of the opener — always names the number.
    static func expectationHint(voice: AgentVoice, ctx: Context) -> String {
        switch voice {
        case .shark:
            return "We're at \(ctx.askPerYear) a year over \(ctx.askYears). \(ctx.askTotal) total. Don't come back under it."
        case .professional:
            return "Our number is \(ctx.askPerYear) a year across \(ctx.askYears) years — \(ctx.askTotal). That's where the comparables sit."
        case .friendly:
            return "We're thinking \(ctx.askPerYear) a year for \(ctx.askYears). \(ctx.askTotal) all in. Reasonable, right?"
        case .oldSchool:
            return "\(ctx.askPerYear) a year, \(ctx.askYears) years, \(ctx.askTotal) on the whole thing. Fair number, fairly arrived at."
        }
    }

    // MARK: Refusal

    /// The client will not come to the table — said in the chat, in character,
    /// with the reason showing.
    static func refusalLine(voice: AgentVoice, reason: AgentRefusalReason, ctx: Context) -> String {
        let core = "My client has no interest in negotiating with this team right now."
        let flavor: [String]
        switch reason {
        case .benched:
            flavor = [
                "He hasn't taken a meaningful snap all year. You want to talk money — start by playing him.",
                "You put him in a baseball cap on Sundays. There's nothing to discuss until that changes.",
                "Contract talk with a man you won't start? That conversation is going to be short."
            ]
        case .losingCulture:
            flavor = [
                "He's watched that building lose for long enough. He's not signing up for more of it.",
                "Win a few games and call me back. He's done buying promises.",
                "There's nothing wrong with the money. There's something wrong with the record."
            ]
        case .wantsOut:
            flavor = [
                "Frankly, he wants out. I'd be doing him a disservice to sit down with you.",
                "He's made his decision about that locker room, and it isn't going to change over a number.",
                "He's asked me to find him a new address, not a new contract."
            ]
        case .ridingIntoRetirement:
            flavor = [
                "He's at the end of the road and he'd like to choose how it ends. Not over the phone with you.",
                "At his age this is the last contract of a life. He's not rushing it, and neither am I.",
                "He's weighing whether there's a next season at all. Give the man his winter."
            ]
        case .ringChasing:
            // The never-sign line has to close the door on MONEY specifically,
            // or the user reads it as a hard negotiation and keeps bidding.
            flavor = [
                "And before you ask — it isn't the money. He's given that building his best years and watched it lose them. He wants to play in January.",
                "There's no number here. He's not signing five more years of this. Win something and we'll talk.",
                "You could offer him every dollar you have. He'd still be watching the playoffs on television, and he knows it."
            ]
        }
        let sign: String
        switch voice {
        case .shark:        sign = "Don't call back this week."
        case .professional: sign = "I'll let you know if that changes."
        case .friendly:     sign = "Nothing personal — you know I'd tell you if there was room."
        case .oldSchool:    sign = "I've told you straight, which is more than most would."
        }
        return "\(core) \(flavor.randomElement()!) \(sign)"
    }

    // MARK: Pestering

    /// **The answer to an offer tabled at a man who already said no.**
    ///
    /// One line per escalation tier rather than a random pool, on purpose: the
    /// whole point of pestering is that it gets WORSE, and a pool would let the
    /// third attempt read softer than the first. `attempt` is 1-based.
    ///
    /// Tier 3 deliberately says out loud what the model is doing to the price —
    /// the ask has been ratcheting 6 % a round this whole time, and an agent who
    /// never mentions it is a mechanic the user cannot learn.
    static func pesteringLine(
        voice: AgentVoice,
        reason: AgentRefusalReason,
        attempt: Int,
        ctx: Context
    ) -> String {
        // The never-sign stance gets its own first answer. On the fourth of the
        // reasons a man can decline, "not interested" is a negotiating position
        // the user is right to test; on THIS one it is a fact about the standings
        // that no offer touches, and the line has to say so before the user
        // spends an offseason bidding against a wall.
        if attempt <= 1, reason.neverSignsAtAnyPrice {
            switch voice {
            case .shark:
                return "You didn't hear me. There is no number. Put a blank cheque on that table and he'd still be watching January from his couch."
            case .professional:
                return "I have to stop you. I understand the instinct, but money genuinely is not the variable here — the standings are. I can't take this to him."
            case .friendly:
                return "Oh, friend. That's a lot of money and it isn't the thing. He wants to play in January. That's all he's asked me for."
            case .oldSchool:
                return "You're answering a question he didn't ask. He wants to win something before he's done. You can't write that on a contract."
            }
        }

        switch max(1, attempt) {
        case 1:
            switch voice {
            case .shark:
                return "I told you — my client isn't interested. Don't waste our time."
            case .professional:
                return "I appreciate the effort, but I was clear: this isn't a money conversation. I won't be taking that to him."
            case .friendly:
                return "Ah, come on now. I said no, and I meant it kindly. Put the pen down."
            case .oldSchool:
                return "I gave you a straight answer. A straight answer deserves to be heard the first time."
            }
        case 2:
            switch voice {
            case .shark:
                return "Are you listening, or just talking? Same answer. \(ctx.playerFirst) is not interested, and every call makes this more expensive."
            case .professional:
                return "This is the second offer I've had to decline on the same grounds. I'd rather not do it a third time."
            case .friendly:
                return "You're a stubborn one. I like you, but he's not moving — and he's hearing about these calls."
            case .oldSchool:
                return "Twice now. In my day a man took no for an answer and kept his dignity."
            }
        default:
            switch voice {
            case .shark:
                return "Enough. \(ctx.playerFirst) knows exactly how many times you've called and exactly what you've offered, and neither one has helped. If we ever DO talk, the number starts higher than it did today."
            case .professional:
                return "I have to be blunt. This is now doing damage — to the relationship, and to the price. My client hears about every one of these."
            case .friendly:
                return "I'm going to be honest with you because I like you: he's insulted now. Not by the money. By the not-listening."
            case .oldSchool:
                return "You've asked the same question four different ways and got the same answer four times. It costs a man something to keep being told no in his own building."
            }
        }
    }

    /// What a client who just won a prove-it bet opens with. The one line in
    /// this file that exists to make a MECHANIC legible: the user signed him
    /// short and cheap last winter and is about to find out what that bought.
    static func provenBetLine(voice: AgentVoice, ctx: Context) -> String {
        switch voice {
        case .shark:
            return "Last year you wanted him on a one-year deal. He took it, he bet on himself, and he won. \(ctx.askPerYear) a year. That's not an opening number."
        case .professional:
            return "We agreed a short deal so the market could price him properly. It has. \(ctx.askPerYear) a year over \(ctx.askYears) — the season speaks for itself."
        case .friendly:
            return "Remember what I said last winter? He'd play his way back. Well — he did. \(ctx.askPerYear) a year, and I think you knew that was coming."
        case .oldSchool:
            return "He bet on himself when nobody else would, and the man was right. \(ctx.askPerYear) a year. I'd have asked for more."
        }
    }

    // MARK: Counters

    /// A counter-offer, spoken. The number the engine put on the counter card is
    /// in the sentence — `ctx.askPerYear` is that counter, not the opener.
    static func counterLine(voice: AgentVoice, tone: AgentToneKey, ctx: Context) -> String {
        switch tone {
        case .insulted:
            return insultedLine(voice: voice, ctx: ctx)
        case .hardline:
            return hardlineLine(voice: voice, ctx: ctx)
        case .eager:
            return eagerLine(voice: voice, ctx: ctx)
        case .professional, .refusing:
            return professionalLine(voice: voice, ctx: ctx)
        }
    }

    private static func insultedLine(voice: AgentVoice, ctx: Context) -> String {
        let msgs: [String]
        switch voice {
        case .shark:
            msgs = [
                "That offer is an insult — my client is worth twice that. \(ctx.offerPerYear) a year? We're at \(ctx.askPerYear), and after that we're not coming down again.",
                "\(ctx.offerPerYear). You said that out loud. \(ctx.askPerYear) a year, and my patience just got shorter.",
                "Do not do that again. \(ctx.askPerYear) a year over \(ctx.askYears) — that's the number, and it hardens every time you lowball me."
            ]
        case .professional:
            msgs = [
                "I'll be honest, \(ctx.offerPerYear) isn't in the neighborhood of the market. We're at \(ctx.askPerYear) a year and I'd rather not move off it again.",
                "That number would be the worst deal at his position in the league. \(ctx.askPerYear) over \(ctx.askYears) years. Let's be serious.",
                "I can't take \(ctx.offerPerYear) back to him without losing his trust. \(ctx.askPerYear) a year."
            ]
        case .friendly:
            msgs = [
                "Come on — \(ctx.offerPerYear)? He'd be hurt if I even read that to him. \(ctx.askPerYear) a year, and I'm holding there now.",
                "That one stings. I want this done, but not at \(ctx.offerPerYear). We're at \(ctx.askPerYear).",
                "You're going to make me the bad guy in his kitchen. \(ctx.askPerYear) a year over \(ctx.askYears)."
            ]
        case .oldSchool:
            msgs = [
                "Son, that offer is an insult — he's worth twice that. \(ctx.askPerYear) a year, and I'm not softening it after that.",
                "I've been at this table thirty years and I don't forget a number like \(ctx.offerPerYear). \(ctx.askPerYear) a year.",
                "That's how you lose a good man for nothing. \(ctx.askPerYear) over \(ctx.askYears) years. The ask goes up, not down, from here."
            ]
        }
        return msgs.randomElement()!
    }

    private static func hardlineLine(voice: AgentVoice, ctx: Context) -> String {
        let msgs: [String]
        switch voice {
        case .shark:
            msgs = [
                "We're thinking \(ctx.askPerYear) a year. That's what elite \(ctx.position)s make. I'm not selling him for less.",
                "\(ctx.askPerYear) over \(ctx.askYears). Your \(ctx.offerPerYear) is a starting point, not a deal.",
                "The number is \(ctx.askPerYear) a year. I've got other calls today."
            ]
        case .professional:
            msgs = [
                "We're at \(ctx.askPerYear) a year across \(ctx.askYears) years. Your \(ctx.offerPerYear) is short of every comparable I have.",
                "\(ctx.askPerYear) annually. I've moved once already — there's a floor under this.",
                "Here's the revision: \(ctx.askPerYear) a year. I'd like to close, but not from where you are."
            ]
        case .friendly:
            msgs = [
                "I want to get this done, I really do — but it has to start with a \(ctx.askPerYear).",
                "You're at \(ctx.offerPerYear), we're at \(ctx.askPerYear). That's a real gap and I can't wish it away.",
                "\(ctx.askPerYear) a year. Meet me and we'll all be at his signing dinner."
            ]
        case .oldSchool:
            msgs = [
                "\(ctx.askPerYear) a year. I've priced men like him for thirty years and that's what he is.",
                "You're at \(ctx.offerPerYear). I've been at \(ctx.askPerYear) since the first phone call. One of us is moving.",
                "The number stays \(ctx.askPerYear). Loyalty is not a discount coupon."
            ]
        }
        return msgs.randomElement()!
    }

    private static func professionalLine(voice: AgentVoice, ctx: Context) -> String {
        let msgs: [String]
        switch voice {
        case .shark:
            msgs = [
                "Better. \(ctx.askPerYear) a year and we're shaking hands today.",
                "Progress. Get to \(ctx.askPerYear) over \(ctx.askYears) and I stop taking other calls.",
                "You moved, so I'll move. \(ctx.askPerYear) a year."
            ]
        case .professional:
            msgs = [
                "That's constructive. We've come down to \(ctx.askPerYear) a year over \(ctx.askYears) — that should work for both sides.",
                "Appreciate the movement. Revised ask: \(ctx.askPerYear) annually. I think that's the deal.",
                "We're close. \(ctx.askPerYear) a year, \(ctx.askTotal) total. Take a look."
            ]
        case .friendly:
            msgs = [
                "Now we're talking. \(ctx.askPerYear) a year and I'll call him right now.",
                "Look at us. \(ctx.askPerYear) over \(ctx.askYears) — say yes and I'll stop bothering you.",
                "That's a real offer, thank you. Get me to \(ctx.askPerYear) and it's done."
            ]
        case .oldSchool:
            msgs = [
                "Sensible. \(ctx.askPerYear) a year and we shake on it like men.",
                "That's how it's supposed to go. \(ctx.askPerYear) over \(ctx.askYears) and I'll stop talking.",
                "Good faith deserves good faith. \(ctx.askPerYear) a year closes this."
            ]
        }
        return msgs.randomElement()!
    }

    private static func eagerLine(voice: AgentVoice, ctx: Context) -> String {
        let msgs: [String]
        switch voice {
        case .shark:
            msgs = [
                "Fine. \(ctx.askPerYear) a year and I'll have him in the building tomorrow.",
                "One more step. \(ctx.askPerYear) and this is over.",
                "\(ctx.askPerYear). Say the word."
            ]
        case .professional:
            msgs = [
                "We're one number apart — \(ctx.askPerYear) a year and I'll recommend he sign it.",
                "This is the last revision from my side: \(ctx.askPerYear) annually.",
                "\(ctx.askPerYear) a year. I'd take that to him with a recommendation."
            ]
        case .friendly:
            msgs = [
                "\(ctx.askPerYear) and I'm ordering the cake. Come on.",
                "So close. \(ctx.askPerYear) a year — he'll say yes before I finish the sentence.",
                "Meet me at \(ctx.askPerYear) and we're done, my friend."
            ]
        case .oldSchool:
            msgs = [
                "\(ctx.askPerYear). That's a handshake number and you know it.",
                "One more inch. \(ctx.askPerYear) a year and I'll tell him it's a good deal.",
                "\(ctx.askPerYear). Let's finish it before somebody says something clever."
            ]
        }
        return msgs.randomElement()!
    }

    // MARK: Years pushback

    /// The agent will not sign his man to a deal longer than his body has left.
    static func yearsPushbackLine(voice: AgentVoice, age: Int, requestedYears: Int, maxYears: Int, ctx: Context) -> String {
        switch voice {
        case .shark:
            return "\(requestedYears) years at \(age)? No. \(maxYears) is the ceiling — here's the revised ask at \(ctx.askPerYear) a year."
        case .professional:
            return "At \(age), \(ctx.playerFirst) isn't signing a \(requestedYears)-year commitment. \(maxYears) years max, \(ctx.askPerYear) annually."
        case .friendly:
            return "\(requestedYears) years? He'd be limping through the last two. Let's say \(maxYears), at \(ctx.askPerYear) a year."
        case .oldSchool:
            return "I've seen what year \(requestedYears) does to a \(age)-year-old. \(maxYears) years, \(ctx.askPerYear) a year. That's honest."
        }
    }

    // MARK: Close

    /// Acceptance, in the tone of the JOURNEY — the deal being good is not the
    /// same as the negotiation having been good.
    static func acceptLine(voice: AgentVoice, tone: AgentToneKey, ctx: Context) -> String {
        switch tone {
        case .eager:
            let msgs: [String]
            switch voice {
            case .shark:
                msgs = ["Now that's how you do business. \(ctx.signedTotal) over \(ctx.signedYears) — he'll be there in the morning.",
                        "Painless. \(ctx.signedPerYear) a year, done. Pleasure."]
            case .professional:
                msgs = ["Great to get this done — can't wait for next season. \(ctx.signedPerYear) a year, \(ctx.signedTotal) total.",
                        "Clean process, fair number. \(ctx.playerFirst) signs at \(ctx.signedPerYear) a year and we're all better for it."]
            case .friendly:
                msgs = ["Oh, he's going to be thrilled! \(ctx.signedPerYear) a year — I'm calling him right now.",
                        "That's what I'm talking about. \(ctx.signedTotal) over \(ctx.signedYears). Can't wait for next season."]
            case .oldSchool:
                msgs = ["That's a deal both sides can be proud of. \(ctx.signedPerYear) a year. He'll earn every dollar.",
                        "Done properly, and quickly. \(ctx.signedTotal) over \(ctx.signedYears) years. Good doing business."]
            }
            return msgs.randomElement()!

        case .professional:
            let msgs: [String]
            switch voice {
            case .shark:
                msgs = ["We'll take it. \(ctx.signedPerYear) a year. He signs today.",
                        "That works. \(ctx.signedTotal) over \(ctx.signedYears). Send the paper."]
            case .professional:
                msgs = ["That's a deal. \(ctx.signedPerYear) a year, \(ctx.signedTotal) total. I'll get it signed.",
                        "Agreed. Fair outcome for both sides at \(ctx.signedPerYear) annually."]
            case .friendly:
                msgs = ["Good, good — \(ctx.signedPerYear) a year. He'll be happy with that.",
                        "Deal. \(ctx.signedTotal) over \(ctx.signedYears). Thanks for working with me."]
            case .oldSchool:
                msgs = ["Agreed. \(ctx.signedPerYear) a year. That's a contract, not a favour.",
                        "We have a deal at \(ctx.signedTotal). Shake on it."]
            }
            return msgs.randomElement()!

        default:
            // Hardline / insulted journey — he signs, but he remembers.
            let msgs: [String]
            switch voice {
            case .shark:
                msgs = ["...fine. We'll go with this. \(ctx.signedPerYear) a year. He'll remember how hard you made it.",
                        "\(ctx.rounds) rounds for \(ctx.signedPerYear). He signs. That's all I'll say about it."]
            case .professional:
                msgs = ["...fine. We'll go with this. \(ctx.signedPerYear) a year, \(ctx.signedTotal) total. It's not where we wanted to land.",
                        "He'll sign it. For the record, we came down further than you did."]
            case .friendly:
                msgs = ["Alright. He'll take it. I won't pretend he's dancing about it at \(ctx.signedPerYear).",
                        "\(ctx.signedTotal) over \(ctx.signedYears). He'll do it for the room, not for the number."]
            case .oldSchool:
                msgs = ["He'll sign. Grudgingly. \(ctx.signedPerYear) a year, after \(ctx.rounds) rounds of this.",
                        "Fine. \(ctx.signedTotal). I've seen teams treat good men better."]
            }
            return msgs.randomElement()!
        }
    }

    /// The note a begrudging close leaves on the player.
    static func lingeringNote(ctx: Context) -> String {
        let msgs = [
            "Signed below his ask — he still thinks he's owed more.",
            "Took the deal, but the negotiation left a mark.",
            "Wants more. Signed anyway, and hasn't forgotten it."
        ]
        return msgs.randomElement()!
    }

    // MARK: Endings

    static func walkAwayLine(voice: AgentVoice, ctx: Context) -> String {
        switch voice {
        case .shark:
            return "We're done. \(ctx.playerFirst) will find his money somewhere with a spine."
        case .professional:
            return "I don't think we're going to bridge this. \(ctx.playerFirst) will explore his options. No hard feelings."
        case .friendly:
            return "Ah, that's a shame. Truly. \(ctx.playerFirst) is going to look around."
        case .oldSchool:
            return "We've gone round enough. \(ctx.playerFirst) will take his chances elsewhere."
        }
    }

    static func brokenOffLine(voice: AgentVoice, ctx: Context) -> String {
        switch voice {
        case .shark:
            return "That's it. Don't call again this offseason — \(ctx.playerFirst) is done talking to you."
        case .professional:
            return "I'm ending this. We won't be revisiting it before the new league year."
        case .friendly:
            return "I can't keep taking these to him. We're going quiet until next offseason."
        case .oldSchool:
            return "You just told that man what you think of him. My phone's off until next year."
        }
    }

    /// What the front office says when it opens with an offer.
    static func gmOfferLine(round: Int, playerFirst: String) -> String {
        round <= 1
            ? "Here's where we are on \(playerFirst)."
            : "We've moved. Take another look."
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
