import Foundation

// MARK: - Agent Dialogue Library (#86)
//
// **What the player WANTS, said out loud, in his agent's voice.**
//
// The dialogue that shipped with the Contact Agent wave had one axis: the four
// agent voices. Every WR, every safety, every 34-year-old captain and every
// mercenary heard the same nine sentences per site, so the chat taught the user
// about the AGENT and nothing at all about the MAN. That is backwards — the
// agent is a hired mouth; the client is the thing the user has to learn to read.
//
// This file adds the second axis. ``AgentDesire`` is derived (never stored) from
// data the demand model already reads, one primary desire per player, and every
// high-traffic line names it: the money client's shark talks about the top of
// the chart, the ring-chaser's friendly agent tells you he would take less for a
// contender, the security-minded veteran's old-school man asks for ink. **The
// user is meant to work out what a player wants by how his agent talks**, and
// then price that.
//
// ## Structure
//
// Most sites are COMPOSED from two or three pools rather than written as whole
// lines. An opener is `greeting + desire + number hint`; a counter is
// `desire body + number clause`. Composition is what makes ~470 authored lines
// cover thousands of distinct bubbles, and it is the pattern the original file
// already used for `opener` and `refusalLine` — only now the middle part is
// about the client instead of about nobody.
//
// ## Ownership
//
// **Nothing here computes anything.** No money, no tone, no verdict, no
// eligibility. `ContractNegotiationEngine` owns all of that and hands this file
// a tone key, a desire and a `Context` of pre-formatted strings. If a line wants
// a number it interpolates one the engine already produced, so the sentence and
// the offer card underneath it can never disagree.

// MARK: - Desire

/// **What this player is actually negotiating for.**
///
/// Derived, never stored: every input is something the demand model already
/// reads off the player row or the `ContractDemand`, so a desire costs no
/// SwiftData migration and cannot drift from the money. Deterministic by
/// construction — there is no roll anywhere in ``primary(player:demand:)``, only
/// a priority ladder — which is what lets the same conversation replay in the
/// same words.
///
/// ## The ladder
///
/// | # | test | desire |
/// |---|---|---|
/// | 1 | `demand.isProveIt` | ``proveIt`` |
/// | 2 | `stance == .legacyVeteran` | ``legacy`` |
/// | 3 | `stance == .ringChaser` | ``winning`` |
/// | 4 | injury history vs age (``isSecurityDriven``) | ``security`` |
/// | 5 | the calendar (``isTermDriven``) | ``term`` |
/// | 6 | `personality.motivation` | money / winning / statsRole / loyalty |
///
/// Order matters and is deliberate: the first five are *situations a man is in*,
/// which override *what he generally plays for*. A money-motivated receiver with
/// three knee surgeries talks about guarantees, because that is what a man in
/// that chair actually talks about.
enum AgentDesire: String, CaseIterable {

    /// The cheque is the conversation. Top of the position's chart.
    case money

    /// A ring. He is bidding on your roster as much as you are bidding on him.
    case winning

    /// The ball, the snaps, the job. He wants a defined role in writing.
    case statsRole

    /// One club, one city, one uniform. He does not want to move house.
    case loyalty

    /// How it ends. Respect, a contender, and a finish worth remembering.
    case legacy

    /// Guaranteed money. He has been hurt, and he is not earning it twice.
    case security

    /// A short, clause-heavy bet on himself and a stage to win it on.
    case proveIt

    /// The years are the argument. When he is free again matters more than the
    /// number.
    case term

    // MARK: Derivation

    /// The one desire this conversation is about.
    static func primary(player: Player, demand: ContractDemand) -> AgentDesire {
        // 1. The bet he is asking to make. The engine already graded it.
        if demand.isProveIt { return .proveIt }
        // 2-3. The two stances that ARE a desire.
        if demand.stance == .legacyVeteran { return .legacy }
        if demand.stance == .ringChaser { return .winning }
        // 4. The body he is protecting.
        if isSecurityDriven(player) { return .security }
        // 5. The calendar.
        if isTermDriven(player: player, demand: demand) { return .term }
        // 6. What he plays for, when nothing louder is happening to him.
        switch player.personality.motivation {
        case .money:   return .money
        case .winning: return .winning
        case .stats:   return .statsRole
        // Fame wants the spotlight, and the spotlight is touches — a man who
        // wants to be famous wants the ball, not a bigger bank balance.
        case .fame:    return .statsRole
        case .loyalty: return .loyalty
        }
    }

    /// He has been carried off enough fields to negotiate like it.
    ///
    /// Three doors, all of them a count of real `InjuryRecord`s against his age:
    /// a chronically broken man at any age, a twice-hurt man on the wrong side of
    /// 29, and any veteran of 32+ carrying a single serious history. Nothing here
    /// is a roll.
    static func isSecurityDriven(_ player: Player) -> Bool {
        let injuries = player.injuryHistory.count
        if injuries >= 3 { return true }
        if injuries >= 2 && player.age >= 29 { return true }
        if injuries >= 1 && player.age >= 32 { return true }
        return false
    }

    /// The length of the deal is the live argument.
    ///
    /// Two shapes: the veteran who will not sign the rest of his thirties away
    /// (and whose `maxContractYears` the engine is already capping), and the
    /// young man who has been here long enough to want locking up properly.
    static func isTermDriven(player: Player, demand: ContractDemand) -> Bool {
        if player.age >= 32 { return true }
        if player.age <= 25, demand.askYears >= 4, player.loyaltyYears >= 2 { return true }
        return false
    }
}

// MARK: - Line Site

/// One place in a conversation a line can be said.
///
/// The raw value is the persistence key for ``DialogueSelector``'s
/// no-immediate-repeat memory, so it is written down rather than derived and
/// must stay stable: a renamed case would only forget one thread's last pick,
/// but it would forget it silently.
enum DialogueSite: String {
    case openGreeting
    case openDesire
    case openHint
    case counterBody
    case counterNumber
    case acceptBody
    case acceptNumber
    case refuseCore
    case refuseFlavor
    case refuseSign
    case pester
    case reopenGreeting
    case provenBet
    case walkAway
    case brokenOff
    case yearsPushback
    case lingering
    case gmOffer
    /// The front office asking a man under contract to take less (#102).
    case payCutAsk
    case payCutAccept
    case payCutCounter
    case payCutRefuse
    case payCutRelease
}

// MARK: - Selector

/// **Which of the variants gets said, and why it is the same one next time.**
///
/// Seeded on `(threadID, round, site)` rather than `randomElement()`, for the
/// reason `ContractDemand` is deterministic: a transcript is persisted and
/// re-read, and a conversation that quotes a different sentence every time the
/// sheet is opened is not a conversation. Two different players' threads diverge
/// because the thread UUID is in the seed; two rounds of the same thread diverge
/// because the round is.
///
/// A reference type on purpose — the view builds several of its lines inside
/// closures, which cannot capture an `inout` struct.
///
/// **No-immediate-repeat.** The last index picked at each site rides on the
/// thread (`NegotiationThread.lastLineIndex`, an additive optional). Without it
/// a four-round negotiation would say the same hardline sentence twice in a row
/// roughly one time in four, which is exactly the thing this whole wave exists
/// to stop being noticeable.
final class DialogueSelector {

    private let threadSeed: UInt64
    private let round: Int

    /// Site key -> last index chosen. Handed back to the caller to persist.
    private(set) var lastIndex: [String: Int]

    init(threadID: UUID, round: Int, lastIndex: [String: Int]?) {
        self.threadSeed = DialogueSelector.hash(uuid: threadID)
        self.round = round
        self.lastIndex = lastIndex ?? [:]
    }

    /// One line from a pool, stable for this `(thread, round, site)`.
    ///
    /// - Parameter key: an extra discriminator for sites whose pool depends on
    ///   something else (the counter's number clause differs per tone). Keeps
    ///   the repeat memory per-pool rather than per-site.
    func pick(_ site: DialogueSite, key: String = "", from pool: [String]) -> String {
        guard let only = pool.first else { return "" }
        guard pool.count > 1 else { return only }

        let memoryKey = key.isEmpty ? site.rawValue : "\(site.rawValue).\(key)"
        var index = Int(seed(for: memoryKey) % UInt64(pool.count))
        if lastIndex[memoryKey] == index {
            index = (index + 1) % pool.count
        }
        lastIndex[memoryKey] = index
        return pool[index]
    }

    // MARK: Seeding

    /// FNV-1a over the thread UUID, the site key and the round.
    ///
    /// Not `hashValue` for the reason `AgentPersona.forPlayer` documents at
    /// length: Swift re-seeds its hasher every launch, so a "deterministic"
    /// choice built on it re-rolls on every app start.
    private func seed(for key: String) -> UInt64 {
        var hash = threadSeed
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        hash ^= UInt64(bitPattern: Int64(round)) &* 0x9E37_79B9_7F4A_7C15
        hash = hash &* 0x0000_0100_0000_01b3
        return hash
    }

    private static func hash(uuid: UUID) -> UInt64 {
        let b = uuid.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

// MARK: - The Library

/// Every line pool in the game's contract chat.
///
/// Pure content. Each function returns the variants for one (site, voice,
/// desire, tone) cell; ``DialogueSelector`` decides which one is said and
/// ``AgentDialogue`` assembles the parts.
enum AgentDialogueLibrary {

    typealias Ctx = AgentDialogue.Context

    // MARK: - Opening: greeting

    /// The hello. Short on purpose — it is one third of a three-part line.
    static func openGreeting(voice: AgentVoice, isExtension: Bool) -> [String] {
        switch voice {
        case .shark:
            return isExtension
                ? ["Let's not waste each other's afternoon.",
                   "You called, so you already know this is going to hurt."]
                : ["You're the fourth call today. Make it count.",
                   "Let's be quick. It's a seller's market and my client is the product."]
        case .professional:
            return isExtension
                ? ["Thanks for reaching out.",
                   "Appreciate the call — let's get straight to it."]
                : ["Thanks for the interest.",
                   "Good to talk. You called early, and that counts for something."]
        case .friendly:
            return isExtension
                ? ["Hey! Great to hear your voice.",
                   "Glad you called — I was going to call you."]
                : ["Hey there. He had a good visit, by the way.",
                   "Thanks for calling. He liked the place, he liked the people."]
        case .oldSchool:
            return isExtension
                ? ["I'll say it plainly, the way I always do.",
                   "Thirty years I've done this, so I'll skip the dance."]
                : ["Let's talk plainly.",
                   "I've sat in a lot of these rooms. This one's worth sitting in."]
        }
    }

    // MARK: - Opening: what he wants

    /// **The heart of the wave.** What the client is after, in his agent's
    /// register. Also reused by the stance-lift reopener, which is the same
    /// sentence said a second time now that the door is open.
    static func openDesire(voice: AgentVoice, desire: AgentDesire, ctx: Ctx) -> [String] {
        switch desire {

        case .money:
            switch voice {
            case .shark:
                return ["\(ctx.playerFirst) didn't take up football for the love of the grass — he came to get paid, and this is the window.",
                        "My client is a business, and the business is having a good year. Pay him like it."]
            case .professional:
                return ["\(ctx.playerFirst) is direct about it: he plays this game for the money, and he wants to sit at the top of the position's chart.",
                        "He isn't shy about what he's after. The cheque is the conversation — fit is a footnote."]
            case .friendly:
                return ["He loves the room, he loves the coaches. He also wants to be paid, and I'd rather say that than pretend otherwise.",
                        "He's had a number in his head since August. I've tried to talk him off it. I lost."]
            case .oldSchool:
                return ["He plays for the paycheck. That's not a flaw, it's honest, and an honest man is easier to deal with.",
                        "I've represented men who wanted a statue. This one wants the money, and he's earned the right to ask."]
            }

        case .winning:
            switch voice {
            case .shark:
                return ["He wants January. If your roster isn't going there, the number gets very large very quickly.",
                        "Money is the easy part with him. The hard part is convincing him you won't win six games again."]
            case .professional:
                return ["\(ctx.playerFirst) is chasing a ring, plainly. Show us the roster's direction and the money conversation gets easier.",
                        "He weighs contenders first and dollars second. That's rare, and it's real — don't waste it."]
            case .friendly:
                return ["Honestly? He'd take less to chase a ring. Show him the roster's going somewhere and you'll save yourself money.",
                        "He watched the playoffs from his couch last winter and hated every minute. That's what you're bidding against."]
            case .oldSchool:
                return ["He wants to win. In thirty years I've met maybe a dozen who meant it, and he's one of them.",
                        "You can't buy a man like this. You can only be the team worth signing with."]
            }

        case .statsRole:
            switch voice {
            case .shark:
                return ["He wants the ball. Write the role down or write a bigger cheque — your choice.",
                        "Snaps first, money second. Take him off the field in the fourth quarter and you'll hear from me by Tuesday."]
            case .professional:
                return ["The role matters as much as the money here. He wants to be the first read, not a package player.",
                        "We'll want to talk usage — touches, snap share, how he's used inside the twenty. Then we'll talk dollars."]
            case .friendly:
                return ["He wants to be a guy, you know? Not a rotation piece. Tell me he's a starter and half my job is done.",
                        "He reads the box score before the standings. Feed him and he's the happiest man in your building."]
            case .oldSchool:
                return ["He wants his touches. Every good one does, and the ones who say otherwise are lying to you.",
                        "Put him on the field and keep him there. That's most of what he's asking for."]
            }

        case .loyalty:
            switch voice {
            case .shark:
                return ["He wants to stay with \(ctx.team). That's leverage I'd rather he hadn't handed you, so don't make him regret it.",
                        "Sentiment is your discount, not mine. He wants one uniform — price it fairly or I'll talk him out of it."]
            case .professional:
                return ["\(ctx.playerFirst) would like to spend his career with \(ctx.team). That should make this easier, not cheaper.",
                        "He isn't shopping. He wants to be here, and he'd like the deal to say he was wanted back."]
            case .friendly:
                return ["His wife has the kids in school here. Nobody wants to pack a house. Let's make this easy.",
                        "He wants to finish with \(ctx.team) — one uniform, one city, the whole thing. Don't make me argue him out of it."]
            case .oldSchool:
                return ["He'd like to play out his days with \(ctx.team). Men used to do that. A few still want to.",
                        "One club, one career. It's out of fashion, and he wants it anyway."]
            }

        case .legacy:
            switch voice {
            case .shark:
                return ["He isn't collecting contracts any more, he's collecting seasons that matter. Respect costs money too.",
                        "This is one of the last deals he'll ever sign. Treat it like it, or somebody else will."]
            case .professional:
                return ["\(ctx.playerFirst) is thinking about how this ends. He wants a contender, and he wants to be treated like what he has been.",
                        "At this stage it's about the last chapter. The dollars matter; being wanted matters more."]
            case .friendly:
                return ["He's counting autumns now, not dollars. He wants the ending to mean something.",
                        "He'd love his number on that wall one day. That's what we're really negotiating."]
            case .oldSchool:
                return ["He's near the end and he knows it. What he wants is to be remembered right.",
                        "I've watched a lot of careers finish badly. This one deserves a proper send-off."]
            }

        case .security:
            switch voice {
            case .shark:
                return ["He's been carried off a field. Guaranteed money or nothing — I don't trade in promises.",
                        "Ink, not intent. Every dollar in this deal has to be one he can't lose to a knee."]
            case .professional:
                return ["Given his medical history, the guarantee structure matters more to us than the headline number.",
                        "We're prioritising guaranteed money. He's had the injuries; he isn't earning the same dollar twice."]
            case .friendly:
                return ["He's been hurt, you know that. He just wants to know his family is safe if the body says no.",
                        "Between us — guarantee it and you can be creative with the rest. The rest isn't what frightens him."]
            case .oldSchool:
                return ["He's played hurt for this league and it has cost him. Guarantee it. That's the whole ask.",
                        "I've watched too many men get released in a training room. Not this one, not while I'm on the phone."]
            }

        case .proveIt:
            switch voice {
            case .shark:
                return ["Short deal, big clauses. He bets on himself and you pay him properly next winter — or somebody else does.",
                        "He doesn't want your safety net, he wants a stage. Give him one year and get out of the way."]
            case .professional:
                return ["We're after a short term with real incentives. He believes the market has him wrong and he'd like to argue the point on the field.",
                        "One or two years, clause-heavy. He's buying back his own market and he's comfortable with the risk."]
            case .friendly:
                return ["He wants to bet on himself. Give him a year, write in the bonuses, and let him go earn it.",
                        "He'd rather have a short deal and a chip on his shoulder than four safe years. That's just how he's built."]
            case .oldSchool:
                return ["He asked me for one year to answer the doubters. I told him it was risky. He told me to make the call anyway.",
                        "Short deal, real incentives. A man that certain of himself usually turns out to be right."]
            }

        case .term:
            switch voice {
            case .shark:
                return ["Years are the argument here, not dollars. He isn't signing away the rest of his thirties for your convenience.",
                        "Tell me the length first. Get that wrong and the money doesn't matter."]
            case .professional:
                return ["The term is the negotiation for us. \(ctx.playerFirst) wants control over when he's on the market again.",
                        "We'll be particular about length. He'd like a deal that expires while he still has a market to go back to."]
            case .friendly:
                return ["It's the years he cares about, honestly. Get the length right and the money sorts itself out.",
                        "He doesn't want to be your dead money in year four. Neither do you, if you think about it."]
            case .oldSchool:
                return ["It's the calendar he's arguing with, not you. Ask him for too many years and he'll say no to good money.",
                        "A contract is a sentence if it's too long. He wants one he can serve out standing up."]
            }
        }
    }

    // MARK: - Opening: the number

    /// The "here's what it takes" close of an opener — always names the ask.
    static func openHint(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["We're at \(ctx.askPerYear) a year over \(ctx.askYears). \(ctx.askTotal) total. Don't come back under it.",
                    "\(ctx.askPerYear) a year, \(ctx.askYears) years. That's the number, not an opening.",
                    "\(ctx.askTotal) across \(ctx.askYears). Round it down and we're finished talking."]
        case .professional:
            return ["Our number is \(ctx.askPerYear) a year across \(ctx.askYears) years — \(ctx.askTotal). That's where the comparables sit.",
                    "We're asking \(ctx.askPerYear) annually over \(ctx.askYears). \(ctx.askTotal) all in, and I can show you the math.",
                    "\(ctx.askYears) years, \(ctx.askTotal). That's \(ctx.askPerYear) a year, and it's defensible."]
        case .friendly:
            return ["We're thinking \(ctx.askPerYear) a year for \(ctx.askYears). \(ctx.askTotal) all in. Reasonable, right?",
                    "Call it \(ctx.askPerYear) a year over \(ctx.askYears) and we can both go home early.",
                    "\(ctx.askTotal) over \(ctx.askYears) years. I know. Hear the number out anyway."]
        case .oldSchool:
            return ["\(ctx.askPerYear) a year, \(ctx.askYears) years, \(ctx.askTotal) on the whole thing. Fair number, fairly arrived at.",
                    "\(ctx.askYears) years at \(ctx.askPerYear). I didn't pick that out of the air.",
                    "\(ctx.askTotal) is the shape of it. I've priced men like him for a long time."]
        }
    }

    // MARK: - Counter: what he wants

    /// The desire half of a counter. Tone-agnostic on purpose: the *frame* is
    /// carried by the number clause, and what the man wants does not change
    /// because the club moved five million.
    static func counterBody(voice: AgentVoice, desire: AgentDesire, ctx: Ctx) -> [String] {
        switch desire {

        case .money:
            switch voice {
            case .shark:
                return ["This is a man who counts what he's paid, and he counts it against the whole league.",
                        "He doesn't want your gratitude. He wants the top of the chart."]
            case .professional:
                return ["The money is the argument with him. It always has been, and he'd tell you so himself.",
                        "He's measuring this against every deal signed at his position in the last two winters."]
            case .friendly:
                return ["He's a lovely man who happens to want every dollar. I can't change either half of that.",
                        "He'll tell you the fit is great. Then he'll ask me what the number was."]
            case .oldSchool:
                return ["He plays for money. Say what you like about that — it makes him easy to understand.",
                        "There's no poetry in this one. There's a figure, and there's whether you meet it."]
            }

        case .winning:
            switch voice {
            case .shark:
                return ["He's chasing January and you're nowhere near it. That costs you.",
                        "Every dollar you're short is a dollar he'd rather spend somewhere with a defense."]
            case .professional:
                return ["He's weighing your roster as hard as he's weighing your offer. Both have to hold up.",
                        "The ring is the thing with him. The money only decides whether he chases it here."]
            case .friendly:
                return ["He'd play for less on a team he believed in. That isn't a threat, it's just true.",
                        "He asked me one question about your building, and it wasn't about money. It was about January."]
            case .oldSchool:
                return ["This one wants a ring more than a raise. You don't meet many.",
                        "He'll take a fair deal from a team that's going somewhere. He'll take nothing from one that isn't."]
            }

        case .statsRole:
            switch voice {
            case .shark:
                return ["He wants the ball and he wants it written down. Snaps are currency to him.",
                        "Pay him like a starter or stop pretending he is one."]
            case .professional:
                return ["Role is half of this negotiation. He wants a defined job, not a package.",
                        "He'll ask me about touches before he asks about guarantees. That's the man you're dealing with."]
            case .friendly:
                return ["He just wants to be used, you know? Give him a real job and he'd sign a napkin.",
                        "He counts his own touches on the plane home. Feed him and you'll never hear from me again."]
            case .oldSchool:
                return ["He wants to play, and he wants it to matter. That isn't vanity, that's a competitor.",
                        "Put him on the field and pay him like you mean to keep him there."]
            }

        case .loyalty:
            switch voice {
            case .shark:
                return ["He wants to stay. Don't mistake that for a discount you're entitled to.",
                        "You have the one thing my other clients don't care about — he likes it there. It's worth money, not everything."]
            case .professional:
                return ["He'd rather do this deal with \(ctx.team) than a better one somewhere else. That should make it easier, not cheaper.",
                        "Staying is the goal here. He's only asking not to be punished for wanting it."]
            case .friendly:
                return ["He doesn't want to move house. He's told me that twice this week.",
                        "You already have his heart. You're haggling over the rest of him."]
            case .oldSchool:
                return ["He wants one club on his whole record. Reward that and he'll never mention money again.",
                        "Loyalty isn't a coupon you clip. It's a thing you pay for, properly, once."]
            }

        case .legacy:
            switch voice {
            case .shark:
                return ["He isn't building a bank balance any more, he's building an ending.",
                        "This is a legacy deal. Cheap legacy deals get remembered badly."]
            case .professional:
                return ["He's thinking about how the story reads when it's over. The number is part of that.",
                        "At this point in a career, respect and money are the same currency."]
            case .friendly:
                return ["He wants to go out the right way. That's really what we're arguing about.",
                        "He'd like the last line of his story written in your colors. Don't make it a sad one."]
            case .oldSchool:
                return ["He's near the finish and he'd like to arrive with his dignity intact.",
                        "This is how a great player gets remembered — by what he was offered at the end of it."]
            }

        case .security:
            switch voice {
            case .shark:
                return ["Guarantee it or keep it. He isn't gambling his body for your flexibility.",
                        "He's been cut before. He knows exactly what unguaranteed money is worth, which is nothing."]
            case .professional:
                return ["The guarantee is the deal for us. The headline can be whatever helps you.",
                        "His medical file is why we're particular. He is not earning the same dollar twice."]
            case .friendly:
                return ["He's been hurt and it frightened him. Guarantee it and he sleeps.",
                        "It isn't greed, it's his family. Put the money in ink and this gets friendly fast."]
            case .oldSchool:
                return ["I've seen men limp out of buildings with nothing. Not this one.",
                        "Guaranteed money is the only honest kind. The rest is a wish with a letterhead."]
            }

        case .proveIt:
            switch voice {
            case .shark:
                return ["He's betting on himself. Short deal, big clauses — pay for the year, not the decade.",
                        "He doesn't want your security. He wants a stage and a scoreboard."]
            case .professional:
                return ["Short term, real incentives. He'd rather be paid for what he's about to do.",
                        "He believes the market has him wrong. He's asking for one year to argue about it."]
            case .friendly:
                return ["He wants to prove something. Write the clauses and let him go chase them.",
                        "One year, a chip on the shoulder and a lot of bonus money. That's his whole plan."]
            case .oldSchool:
                return ["He asked me for a short deal. Men who ask for that are usually right about themselves.",
                        "He'd rather earn it twice than be given it once."]
            }

        case .term:
            switch voice {
            case .shark:
                return ["The years are the fight here. Get them wrong and the number is irrelevant.",
                        "He isn't signing his last good seasons away cheap. Length first."]
            case .professional:
                return ["Term is the sticking point. He wants to be on the market again while he still has one.",
                        "We'll take a strong number on a short deal over a soft one on a long deal, every time."]
            case .friendly:
                return ["It's the calendar he's arguing with. Shorten it and watch how agreeable he gets.",
                        "He doesn't want to be your dead money in year four. That's the whole objection."]
            case .oldSchool:
                return ["It's the length he's minding, not the money. That's rarer than you'd think.",
                        "Too many years and a good deal turns into a bad marriage."]
            }
        }
    }

    // MARK: - Counter: the number

    /// The tone half of a counter — the frame the engine graded, with the
    /// engine's own number in it.
    static func counterNumber(voice: AgentVoice, tone: AgentToneKey, ctx: Ctx) -> [String] {
        switch tone {

        case .hardline:
            switch voice {
            case .shark:
                return ["The number is \(ctx.askPerYear) a year. I've got other calls today.",
                        "\(ctx.askPerYear) over \(ctx.askYears). Your \(ctx.offerPerYear) is a starting point, not a deal.",
                        "\(ctx.askPerYear). That's what elite \(ctx.position)s make, and he's one.",
                        "We're at \(ctx.askPerYear) and I'm not walking it back. \(ctx.askTotal) total."]
            case .professional:
                return ["We're at \(ctx.askPerYear) a year across \(ctx.askYears) years. Your \(ctx.offerPerYear) is short of every comparable I have.",
                        "\(ctx.askPerYear) annually. I've moved once already — there's a floor under this.",
                        "Here's the revision: \(ctx.askPerYear) a year. I'd like to close, but not from where you are.",
                        "\(ctx.askTotal) over \(ctx.askYears). That is a defensible number and \(ctx.offerPerYear) is not."]
            case .friendly:
                return ["I want this done, I really do — but it starts with a \(ctx.askPerYear).",
                        "You're at \(ctx.offerPerYear), we're at \(ctx.askPerYear). That's a real gap and I can't wish it away.",
                        "\(ctx.askPerYear) a year. Meet me there and we'll all be at his signing dinner.",
                        "\(ctx.askTotal) over \(ctx.askYears). Come on, that's not a crazy sentence to say out loud."]
            case .oldSchool:
                return ["\(ctx.askPerYear) a year. I've priced men like him for thirty years and that's what he is.",
                        "You're at \(ctx.offerPerYear). I've been at \(ctx.askPerYear) since the first phone call. One of us is moving.",
                        "The number stays \(ctx.askPerYear). It isn't stubbornness, it's arithmetic.",
                        "\(ctx.askTotal) across \(ctx.askYears) years. Write it down and look at it a while."]
            }

        case .professional, .refusing:
            switch voice {
            case .shark:
                return ["Better. \(ctx.askPerYear) a year and we're shaking hands today.",
                        "Progress. Get to \(ctx.askPerYear) over \(ctx.askYears) and I stop taking other calls.",
                        "You moved, so I'll move. \(ctx.askPerYear) a year.",
                        "\(ctx.askPerYear). That's me cutting into my own client's money, so don't ask twice."]
            case .professional:
                return ["That's constructive. We've come down to \(ctx.askPerYear) a year over \(ctx.askYears).",
                        "Appreciate the movement. Revised ask: \(ctx.askPerYear) annually. I think that's the deal.",
                        "We're close. \(ctx.askPerYear) a year, \(ctx.askTotal) total. Take a look.",
                        "I've shaved it to \(ctx.askPerYear). That's a genuine concession, not a repackaging."]
            case .friendly:
                return ["Now we're talking. \(ctx.askPerYear) a year and I'll call him right now.",
                        "Look at us being reasonable. \(ctx.askPerYear) over \(ctx.askYears) — say yes and I'll stop bothering you.",
                        "That's a real offer, thank you. Get me to \(ctx.askPerYear) and it's done.",
                        "I've moved to \(ctx.askPerYear). I'm going to catch it from him for that, by the way."]
            case .oldSchool:
                return ["Sensible. \(ctx.askPerYear) a year and we shake on it like men.",
                        "That's how it's supposed to go. \(ctx.askPerYear) over \(ctx.askYears) and I'll stop talking.",
                        "Good faith deserves good faith. \(ctx.askPerYear) a year closes this.",
                        "I've come down to \(ctx.askPerYear). I don't do that often and I won't do it again."]
            }

        case .eager:
            switch voice {
            case .shark:
                return ["\(ctx.askPerYear). Say the word.",
                        "One more step. \(ctx.askPerYear) and this is over.",
                        "Fine. \(ctx.askPerYear) a year and I'll have him in the building tomorrow.",
                        "We're one number apart. \(ctx.askPerYear). Don't get clever now."]
            case .professional:
                return ["We're one number apart — \(ctx.askPerYear) a year and I'll recommend he signs it.",
                        "This is the last revision from my side: \(ctx.askPerYear) annually.",
                        "\(ctx.askPerYear) a year. I'd take that to him with a recommendation.",
                        "\(ctx.askTotal) over \(ctx.askYears) and we're finished. That's my final shape."]
            case .friendly:
                return ["\(ctx.askPerYear) and I'm ordering the cake.",
                        "So close. \(ctx.askPerYear) a year — he'll say yes before I finish the sentence.",
                        "Meet me at \(ctx.askPerYear) and we're done, my friend.",
                        "\(ctx.askPerYear). Go on. You know you're going to."]
            case .oldSchool:
                return ["\(ctx.askPerYear). That's a handshake number and you know it.",
                        "One more inch. \(ctx.askPerYear) a year and I'll tell him it's a good deal.",
                        "\(ctx.askPerYear). Let's finish it before somebody says something clever.",
                        "\(ctx.askTotal). Take it, shake my hand, and we'll both sleep tonight."]
            }

        case .insulted:
            switch voice {
            case .shark:
                return ["\(ctx.offerPerYear). You said that out loud. \(ctx.askPerYear) a year, and my patience just got shorter.",
                        "That's an insult. \(ctx.askPerYear), and it hardens every time you lowball me.",
                        "Do not do that again. \(ctx.askPerYear) a year over \(ctx.askYears).",
                        "\(ctx.offerPerYear) buys you a dial tone. \(ctx.askPerYear)."]
            case .professional:
                return ["\(ctx.offerPerYear) isn't in the neighborhood of the market. We're at \(ctx.askPerYear) and I'd rather not move off it again.",
                        "That would be the worst deal at his position in the league. \(ctx.askPerYear) over \(ctx.askYears) years.",
                        "I can't take \(ctx.offerPerYear) back to him without losing his trust. \(ctx.askPerYear) a year.",
                        "That isn't a negotiating position, it's a filing error. \(ctx.askPerYear)."]
            case .friendly:
                return ["Come on — \(ctx.offerPerYear)? He'd be hurt if I even read that to him. \(ctx.askPerYear) a year.",
                        "That one stings. I want this done, but not at \(ctx.offerPerYear). We're at \(ctx.askPerYear).",
                        "You're going to make me the bad guy in his kitchen. \(ctx.askPerYear) over \(ctx.askYears).",
                        "Oh, friend. No. \(ctx.askPerYear) a year — and now I have to tell him you tried \(ctx.offerPerYear)."]
            case .oldSchool:
                return ["Son, that's an insult, and I don't forget a number like \(ctx.offerPerYear). \(ctx.askPerYear) a year.",
                        "That's how you lose a good man for nothing. \(ctx.askPerYear) over \(ctx.askYears) years.",
                        "\(ctx.offerPerYear) is how a club tells a man what it thinks of him. \(ctx.askPerYear).",
                        "The ask goes up from here, not down. \(ctx.askPerYear) a year."]
            }
        }
    }

    // MARK: - Accept: the number

    /// The handshake, with the signed money in it. Graded by the tone of the
    /// JOURNEY, which is `ContractNegotiationEngine.closeTone`'s verdict.
    static func acceptNumber(voice: AgentVoice, tone: AgentToneKey, ctx: Ctx) -> [String] {
        switch tone {

        case .eager:
            switch voice {
            case .shark:
                return ["\(ctx.signedTotal) over \(ctx.signedYears) — he'll be in the building in the morning.",
                        "\(ctx.signedPerYear) a year, done. Pleasure.",
                        "Painless. \(ctx.signedTotal). Send the paper."]
            case .professional:
                return ["\(ctx.signedPerYear) a year, \(ctx.signedTotal) total. Clean process.",
                        "Agreed at \(ctx.signedPerYear) annually. Can't wait for next season.",
                        "\(ctx.signedYears) years, \(ctx.signedTotal). A fair deal, fairly done."]
            case .friendly:
                return ["\(ctx.signedPerYear) a year — I'm calling him right now!",
                        "\(ctx.signedTotal) over \(ctx.signedYears). Oh, he's going to be thrilled.",
                        "Done at \(ctx.signedPerYear). Best phone call I'll make today."]
            case .oldSchool:
                return ["\(ctx.signedPerYear) a year. He'll earn every dollar of it.",
                        "\(ctx.signedTotal) over \(ctx.signedYears) years. Good doing business.",
                        "Done properly, and quickly. \(ctx.signedPerYear) a year."]
            }

        case .professional:
            switch voice {
            case .shark:
                return ["We'll take it. \(ctx.signedPerYear) a year. He signs today.",
                        "That works. \(ctx.signedTotal) over \(ctx.signedYears).",
                        "\(ctx.signedPerYear). Fine. Get it in front of him."]
            case .professional:
                return ["That's a deal. \(ctx.signedPerYear) a year, \(ctx.signedTotal) total. I'll get it signed.",
                        "Agreed. Fair outcome for both sides at \(ctx.signedPerYear) annually.",
                        "\(ctx.signedYears) years at \(ctx.signedPerYear). We're comfortable with that."]
            case .friendly:
                return ["Good, good — \(ctx.signedPerYear) a year. He'll be happy with that.",
                        "Deal. \(ctx.signedTotal) over \(ctx.signedYears). Thanks for working with me.",
                        "\(ctx.signedPerYear) it is. That was almost pleasant."]
            case .oldSchool:
                return ["Agreed. \(ctx.signedPerYear) a year. That's a contract, not a favour.",
                        "We have a deal at \(ctx.signedTotal). Shake on it.",
                        "\(ctx.signedYears) years, \(ctx.signedPerYear) a year. Nothing here to argue with."]
            }

        default:
            switch voice {
            case .shark:
                return ["...fine. \(ctx.signedPerYear) a year. He'll remember how hard you made it.",
                        "\(ctx.rounds) rounds for \(ctx.signedPerYear). He signs. That's all I'll say about it.",
                        "\(ctx.signedTotal). Congratulations, I suppose."]
            case .professional:
                return ["...fine. \(ctx.signedPerYear) a year, \(ctx.signedTotal) total. It isn't where we wanted to land.",
                        "He'll sign it. For the record, we came down further than you did.",
                        "\(ctx.signedYears) years at \(ctx.signedPerYear). Noted, and filed."]
            case .friendly:
                return ["Alright. He'll take it. I won't pretend he's dancing about at \(ctx.signedPerYear).",
                        "\(ctx.signedTotal) over \(ctx.signedYears). He'll do it for the room, not for the number.",
                        "\(ctx.signedPerYear). I'll tell him it was the best I could do. It was."]
            case .oldSchool:
                return ["He'll sign. Grudgingly. \(ctx.signedPerYear) a year, after \(ctx.rounds) rounds of this.",
                        "Fine. \(ctx.signedTotal). I've seen clubs treat good men better.",
                        "\(ctx.signedPerYear) a year. A hard winter for a simple thing."]
            }
        }
    }

    // MARK: - Accept: what it meant to him

    /// What the signature MEANT, in terms of what he wanted. Split on the close
    /// rather than woven through it: a delighted man and a ground-down one want
    /// the same thing and feel completely different about having got it.
    static func acceptBody(
        voice: AgentVoice, desire: AgentDesire, isGrudging: Bool, ctx: Ctx
    ) -> [String] {
        isGrudging
            ? [grudgingAcceptBody(voice: voice, desire: desire, ctx: ctx)]
            : [happyAcceptBody(voice: voice, desire: desire, ctx: ctx)]
    }

    private static func happyAcceptBody(
        voice: AgentVoice, desire: AgentDesire, ctx: Ctx
    ) -> String {
        switch desire {
        case .money:
            switch voice {
            case .shark:        return "He got paid. That's the only review he was ever going to give you."
            case .professional: return "He wanted to be paid properly and he was. Clean outcome."
            case .friendly:     return "He's going to stare at that number all night. Unbearable, in the best way."
            case .oldSchool:    return "He asked for money and you paid it. Simple deals last longest."
            }
        case .winning:
            switch voice {
            case .shark:        return "Now go win something. It's the only thing that keeps a man like this happy."
            case .professional: return "He signed because he believes in where this is going. Don't prove him wrong."
            case .friendly:     return "He didn't even ask me the total, you know. He asked about the schedule."
            case .oldSchool:    return "He signed for the football. Make sure the football is worth it."
            }
        case .statsRole:
            switch voice {
            case .shark:        return "Now use him. That's the other half of this deal and it isn't in writing."
            case .professional: return "He'll expect the role we discussed. That part matters to him as much as the money."
            case .friendly:     return "Just get him the ball and he'll be the happiest man in your building."
            case .oldSchool:    return "Play him. That's what he really bought with this signature."
            }
        case .loyalty:
            switch voice {
            case .shark:        return "He stays. Don't make him regret being sentimental about it."
            case .professional: return "He's exactly where he wanted to be, and the deal says so."
            case .friendly:     return "Nobody's moving house! He's thrilled, his wife is thrilled, I'm thrilled."
            case .oldSchool:    return "One club, one man, one more contract. That's how it ought to go."
            }
        case .legacy:
            switch voice {
            case .shark:        return "He finishes here. Put him in the record book and everybody wins."
            case .professional: return "He gets to write the ending where he wanted to write it. That's worth more than the last million."
            case .friendly:     return "He's going to get emotional about this one. He wanted it to end right."
            case .oldSchool:    return "That's a proper way to see a great player home."
            }
        case .security:
            switch voice {
            case .shark:        return "It's guaranteed. That's all he ever asked for, so now he can stop worrying."
            case .professional: return "The guarantee is what closed this. His family can breathe."
            case .friendly:     return "He'll sleep tonight for the first time since the injury. Thank you for that."
            case .oldSchool:    return "Money in ink. That's what a man wants when he's been hurt for a living."
            }
        case .proveIt:
            switch voice {
            case .shark:        return "One year. He'll make you regret the term, and that's exactly the point."
            case .professional: return "Short deal, clauses in place. He's comfortable — he'd rather earn it."
            case .friendly:     return "He's already talking about next winter. Fair warning."
            case .oldSchool:    return "He bet on himself. Now let's watch the man play."
            }
        case .term:
            switch voice {
            case .shark:        return "The length is right, so the money worked. That was always the order of it."
            case .professional: return "The term is what got this done. He can serve this deal and still have a market after it."
            case .friendly:     return "See? Get the years right and everything else falls over the line."
            case .oldSchool:    return "Sensible length, sensible number. Contracts ought to be that boring."
            }
        }
    }

    private static func grudgingAcceptBody(
        voice: AgentVoice, desire: AgentDesire, ctx: Ctx
    ) -> String {
        switch desire {
        case .money:
            switch voice {
            case .shark:        return "He signs. He'll also know to the dollar what he left on that table."
            case .professional: return "He'll take it. He's a man who counts, and he has counted this."
            case .friendly:     return "He'll sign it. He won't be framing it."
            case .oldSchool:    return "He'll take your money and remember what it wasn't."
            }
        case .winning:
            switch voice {
            case .shark:        return "He signed for the football, not for you. Win, or this gets ugly by November."
            case .professional: return "He accepted because he wants to win here. That's the only reason, and it's a fragile one."
            case .friendly:     return "He's doing this for the room, honestly. Not for that number."
            case .oldSchool:    return "He'll play, and he'll play hard. He'll expect something back on the field."
            }
        case .statsRole:
            switch voice {
            case .shark:        return "He signs under protest. Take him off the field once and you'll find out how far under."
            case .professional: return "He'll sign. He'll also be watching his snap count very closely."
            case .friendly:     return "He'll do it — but he's going to want the ball twice as often now."
            case .oldSchool:    return "He'll take it. You'd better play him like you meant to."
            }
        case .loyalty:
            switch voice {
            case .shark:        return "He stayed anyway. You should be embarrassed by how cheap that was."
            case .professional: return "He signed because he didn't want to leave. Don't confuse that with satisfaction."
            case .friendly:     return "He's staying because it's home. Not because you were generous."
            case .oldSchool:    return "You leaned on his loyalty to save a few dollars. He noticed. So did I."
            }
        case .legacy:
            switch voice {
            case .shark:        return "That's how a great player gets sent off, is it. Cheaply."
            case .professional: return "He'll sign it. A career like his deserved a better last negotiation."
            case .friendly:     return "He'll take it. I just wish the ending had felt bigger than this."
            case .oldSchool:    return "All those years, and it finishes with a haggle. I've seen better manners."
            }
        case .security:
            switch voice {
            case .shark:        return "He signs with less guaranteed than he needed. Pray for his knees."
            case .professional: return "He'll accept. The guarantee is thinner than we wanted, and he knows what that means."
            case .friendly:     return "He'll sign it. He'll also lie awake about it, and so will I."
            case .oldSchool:    return "A man who has been hurt shouldn't have to beg for ink. He signed anyway."
            }
        case .proveIt:
            switch voice {
            case .shark:        return "He'll take it and he'll be gone the second it expires. Enjoy the year."
            case .professional: return "He signs. He's already thinking about the next negotiation, which is now yours to lose."
            case .friendly:     return "He'll do it. But he's writing that number down for next time."
            case .oldSchool:    return "He'll play the year out. Then somebody else will pay him properly."
            }
        case .term:
            switch voice {
            case .shark:        return "Too many years at too small a number. He'll feel every one of them."
            case .professional: return "He accepted the term reluctantly. That length was our concession, not our preference."
            case .friendly:     return "He'll sign it, but that's a long time to feel underpaid."
            case .oldSchool:    return "Long deal, thin money. He'll be counting the seasons. So will I."
            }
        }
    }

    // MARK: - Refusal

    /// He is not coming to the table. Composed core + reason + sign-off.
    static func refuseCore(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["My client has no interest in negotiating with this team right now.",
                    "There's no negotiation to have. He isn't interested."]
        case .professional:
            return ["I have to tell you my client isn't willing to open talks at the moment.",
                    "He's asked me not to take contract calls from this building right now."]
        case .friendly:
            return ["Ah — I have to say no on his behalf, and I'm sorry about it.",
                    "He isn't in a place to talk about a contract just now."]
        case .oldSchool:
            return ["He's told me not to negotiate with you at the minute, and I do what my client asks.",
                    "There'll be no contract talk today. That's his instruction, not mine."]
        }
    }

    static func refuseFlavor(voice: AgentVoice, reason: AgentRefusalReason, ctx: Ctx) -> [String] {
        switch reason {
        case .benched:
            switch voice {
            case .shark:        return ["He hasn't taken a meaningful snap all year. Start him, then call me."]
            case .professional: return ["He hasn't started a game this season. Until that changes there's nothing for us to price."]
            case .friendly:     return ["He's been in a baseball cap on Sundays. You can't talk money to a man you won't play."]
            case .oldSchool:    return ["You've had him standing on a sideline all autumn. That's your answer, not mine."]
            }
        case .losingCulture:
            switch voice {
            case .shark:        return ["Win a few and call me back. He's done buying promises."]
            case .professional: return ["There's nothing wrong with the money. There's something wrong with the record."]
            case .friendly:     return ["He's watched that building lose for a long time now. It's worn him right out."]
            case .oldSchool:    return ["A man can only take so many Novembers like the last one."]
            }
        case .wantsOut:
            switch voice {
            case .shark:        return ["He wants out. Sitting down with you would be malpractice on my part."]
            case .professional: return ["He's made his decision about that locker room, and a number won't move it."]
            case .friendly:     return ["He's asked me to find him a new address, not a new contract. I'm sorry."]
            case .oldSchool:    return ["He's done with the place. I told him to sleep on it. He slept on it."]
            }
        case .ridingIntoRetirement:
            switch voice {
            case .shark:        return ["He's at the end and he'd like to pick how it finishes. Not on this call."]
            case .professional: return ["At his age this is the last contract of a life. He isn't rushing it and neither am I."]
            case .friendly:     return ["He's weighing whether there's another season in him at all. Give the man his winter."]
            case .oldSchool:    return ["He's earned the right to decide when it's over. Let him have it."]
            }
        case .ringChasing:
            // The never-sign line has to close the door on MONEY specifically,
            // or the user reads it as hard bargaining and keeps bidding.
            switch voice {
            case .shark:        return ["And it isn't the money. Put a blank cheque on that table — he'd still be watching January on television."]
            case .professional: return ["This isn't a money conversation. He's given that building his best years and watched them go nowhere. He wants to play in January."]
            case .friendly:     return ["There's no number here, friend. He wants to win something before he's finished."]
            case .oldSchool:    return ["You could offer him everything you have. He wants a season that means something, and you can't write that on a contract."]
            }
        }
    }

    static func refuseSign(voice: AgentVoice) -> [String] {
        switch voice {
        case .shark:
            return ["Don't call back this week.", "We're done for now.", "I'll be direct: stop calling."]
        case .professional:
            return ["I'll let you know if that changes.",
                    "I'd rather be honest than string you along.",
                    "If the situation changes, I'll pick up."]
        case .friendly:
            return ["Nothing personal — you know I'd tell you if there was room.",
                    "I hate saying no to you, I really do.",
                    "Don't take it to heart. It isn't about you."]
        case .oldSchool:
            return ["I've told you straight, which is more than most would.",
                    "That's the truth of it, plainly said.",
                    "You'll get no games from me. Just a no."]
        }
    }

    // MARK: - Pestering

    /// The answer to an offer tabled at a man who already said no. **Escalating
    /// by tier, never softening** — a pool that let attempt three read gentler
    /// than attempt one would break the whole mechanic.
    static func pestering(voice: AgentVoice, tier: Int, ctx: Ctx) -> [String] {
        switch max(1, tier) {
        case 1:
            switch voice {
            case .shark:
                return ["I told you — my client isn't interested. Don't waste our time.",
                        "Same answer as ten minutes ago. He's not interested and money isn't the lever."]
            case .professional:
                return ["I appreciate the effort, but I was clear: this isn't a money conversation. I won't be taking that to him.",
                        "That's a serious offer and it's still the wrong instrument. I have to decline it."]
            case .friendly:
                return ["Ah, come on now. I said no, and I meant it kindly. Put the pen down.",
                        "That's generous of you and it doesn't touch the problem. Truly."]
            case .oldSchool:
                return ["I gave you a straight answer. A straight answer deserves to be heard the first time.",
                        "You've written a number where a conversation was needed. It's still no."]
            }
        case 2:
            switch voice {
            case .shark:
                return ["Are you listening, or just talking? Same answer. \(ctx.playerFirst) is not interested, and every call makes this more expensive.",
                        "Second time. Second no. The price of the first one is already on the table."]
            case .professional:
                return ["This is the second offer I've had to decline on the same grounds. I'd rather not do it a third time.",
                        "I've now said this twice. My client hears about each of these, and it isn't helping you."]
            case .friendly:
                return ["You're a stubborn one. I like you, but he isn't moving — and he's hearing about these calls.",
                        "Twice now, my friend. I'm running out of gentle ways to say it."]
            case .oldSchool:
                return ["Twice now. In my day a man took no for an answer and kept his dignity.",
                        "You've asked the same question in a new suit. Same answer as it wore before."]
            }
        default:
            switch voice {
            case .shark:
                return ["Enough. \(ctx.playerFirst) knows exactly how many times you've called and exactly what you've offered, and neither has helped. If we ever DO talk, the number starts higher than it did today.",
                        "Stop. Every one of these has moved the price, and it hasn't moved it your way."]
            case .professional:
                return ["I have to be blunt. This is now doing damage — to the relationship, and to the price. My client hears about every one of these.",
                        "We're past persistence and into a problem. Each attempt has cost you money you'll pay later."]
            case .friendly:
                return ["I'm going to be honest because I like you: he's insulted now. Not by the money. By the not-listening.",
                        "Please stop. You're making me the man who keeps delivering bad news about you."]
            case .oldSchool:
                return ["You've asked the same question four different ways and had the same answer four times. It costs a man something to keep being told no in his own building.",
                        "There's persistence and there's disrespect, and you've walked from one into the other."]
            }
        }
    }

    /// The never-sign stance gets its own FIRST answer: on the other four
    /// refusals "not interested" is a position the club is right to test; on this
    /// one it is a fact about the standings, and the line has to say so before
    /// the user spends an offseason bidding against a wall.
    static func neverSigns(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["You didn't hear me. There is no number. Put a blank cheque on that table and he'd still be watching January from his couch.",
                    "No. Not at that, not at double it. He isn't selling something you're buying."]
        case .professional:
            return ["I have to stop you. I understand the instinct, but money genuinely is not the variable here — the standings are. I can't take this to him.",
                    "That's a strong offer aimed at the wrong problem. He wants a contender, and you cannot write one into a contract."]
        case .friendly:
            return ["Oh, friend. That's a lot of money and it isn't the thing. He wants to play in January. That's all he's asked me for.",
                    "You're being very kind with the numbers and none of it lands. He wants to win, and that's the whole of it."]
        case .oldSchool:
            return ["You're answering a question he didn't ask. He wants to win something before he's done. You can't write that on a contract.",
                    "Money's the only tool you've brought, and it's the wrong one for this job."]
        }
    }

    // MARK: - Reopen (stance lift)

    /// The door opened. Said before the desire and the number, which the opener
    /// pools supply — a reopen IS an opener, only with history behind it.
    static func reopenGreeting(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["Things have changed, so I'll take the meeting.",
                    "New situation, new call. Don't read too much into it.",
                    "Alright. He's willing to listen now."]
        case .professional:
            return ["Circumstances have moved, and so has he. We're ready to talk.",
                    "Thanks for your patience. He's open to a conversation now.",
                    "The situation is different this time, and so is our answer."]
        case .friendly:
            return ["Good news for once — he's ready to talk!",
                    "Well, look at that. He's come round, and I'm glad.",
                    "Things have got better over there. He noticed. So did I."]
        case .oldSchool:
            return ["Something changed, and a man's entitled to change with it.",
                    "He's had his think. He's ready to sit down.",
                    "You've earned a hearing. That's more than most manage."]
        }
    }

    // MARK: - Proven bet

    /// The client who took a short deal to rebuild his market and delivered. The
    /// one line whose whole job is making a MECHANIC legible: the user wrote that
    /// bet last winter and is about to find out what it bought.
    static func provenBet(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["Last year you wanted him on a short deal. He took it, bet on himself, and won. \(ctx.askPerYear) a year. That is not an opening number.",
                    "You rented him cheap and he made you look clever. That was the last discount. \(ctx.askPerYear).",
                    "The bet paid. \(ctx.askPerYear) a year over \(ctx.askYears), and I'm being polite about it."]
        case .professional:
            return ["We agreed a short deal so the market could price him properly. It has. \(ctx.askPerYear) a year over \(ctx.askYears) — the season speaks for itself.",
                    "He took the prove-it deal and proved it. \(ctx.askPerYear) annually is simply what the tape now says.",
                    "The short contract did its job. \(ctx.askPerYear) a year, \(ctx.askTotal) total, and every comparable backs it."]
        case .friendly:
            return ["Remember what I said last winter? He'd play his way back. Well — he did. \(ctx.askPerYear) a year, and I think you knew it was coming.",
                    "You gave him the year, he gave you the season. \(ctx.askPerYear) now, and no hard feelings either way.",
                    "He bet on himself and you helped him do it. Lovely story. \(ctx.askPerYear) a year."]
        case .oldSchool:
            return ["He bet on himself when nobody else would, and the man was right. \(ctx.askPerYear) a year. I'd have asked for more.",
                    "A short deal is a promise both ways. He kept his half. \(ctx.askPerYear).",
                    "You bought a season cheap and it turned out to be a good one. \(ctx.askPerYear) a year is the bill."]
        }
    }

    // MARK: - Endings

    /// The agent gives up. Voice-only, no desire weave: what a man wanted stops
    /// being the interesting thing at the moment he stops being available, and a
    /// parting line that lectured the club about his ambitions would read as
    /// negotiating after the negotiation.
    static func walkAway(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["We're done. \(ctx.playerFirst) will find his money somewhere with a spine.",
                    "That's it. I'll go and find a club that can count.",
                    "Finished. You had him and you argued yourself out of it."]
        case .professional:
            return ["I don't think we're going to bridge this. \(ctx.playerFirst) will explore his options. No hard feelings.",
                    "We've reached the end of what's useful. He'll look elsewhere.",
                    "This one isn't going to close. I'd rather say so than keep you on the phone."]
        case .friendly:
            return ["Ah, that's a shame. Truly. \(ctx.playerFirst) is going to look around.",
                    "I hate this part. We're going to go and see who else is calling.",
                    "It's not to be, is it. He'll take the meetings he's been offered."]
        case .oldSchool:
            return ["We've gone round enough. \(ctx.playerFirst) will take his chances elsewhere.",
                    "That's the end of it. A pity — this one should have been simple.",
                    "I've said all I usefully can. He'll go where he's wanted."]
        }
    }

    static func brokenOff(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["That's it. Don't call again this offseason — \(ctx.playerFirst) is done talking to you.",
                    "We're finished. My phone doesn't ring for this building until the new league year.",
                    "Done. You'll get nothing from me until the calendar turns."]
        case .professional:
            return ["I'm ending this. We won't be revisiting it before the new league year.",
                    "That closes the conversation. I'd rather not have another like it.",
                    "We're finished for this offseason. I'll be straight: that number did it."]
        case .friendly:
            return ["I can't keep taking these to him. We're going quiet until next offseason.",
                    "Oh, that's done it. I'm sorry — I have to stop answering for a while.",
                    "That's the end of my patience, and I have a lot of it. Talk next year."]
        case .oldSchool:
            return ["You just told that man what you think of him. My phone's off until next year.",
                    "That's beneath a serious club. We're finished until the new league year.",
                    "I've been insulted more politely than that. Talks are over."]
        }
    }

    static func yearsPushback(
        voice: AgentVoice, age: Int, requestedYears: Int, maxYears: Int, ctx: Ctx
    ) -> [String] {
        switch voice {
        case .shark:
            return ["\(requestedYears) years at \(age)? No. \(maxYears) is the ceiling — revised ask is \(ctx.askPerYear) a year.",
                    "You're trying to own his retirement. \(maxYears) years, \(ctx.askPerYear).",
                    "Not \(requestedYears). \(maxYears), at \(ctx.askPerYear) a year, and that's generous of me."]
        case .professional:
            return ["At \(age), \(ctx.playerFirst) isn't signing a \(requestedYears)-year commitment. \(maxYears) years max, \(ctx.askPerYear) annually.",
                    "The term is the problem, not the money. \(maxYears) years is our ceiling at \(ctx.askPerYear) a year.",
                    "\(requestedYears) years at his age prices in a decline we're not selling. \(maxYears), \(ctx.askPerYear)."]
        case .friendly:
            return ["\(requestedYears) years? He'd be limping through the last two. Let's say \(maxYears), at \(ctx.askPerYear) a year.",
                    "That's a lovely offer wrapped around too many years. \(maxYears) and \(ctx.askPerYear), and we're friends again.",
                    "He's \(age), love the enthusiasm — but \(maxYears) years. \(ctx.askPerYear) a year."]
        case .oldSchool:
            return ["I've seen what year \(requestedYears) does to a \(age)-year-old. \(maxYears) years, \(ctx.askPerYear) a year. That's honest.",
                    "Don't sign a man to years he can't play. \(maxYears), at \(ctx.askPerYear).",
                    "At \(age) you buy seasons, not decades. \(maxYears) years, \(ctx.askPerYear) a year."]
        }
    }

    /// The note a begrudging close leaves on the player — the one line the roster
    /// keeps showing after the conversation is over, so it names what he wanted.
    static func lingering(desire: AgentDesire, ctx: Ctx) -> [String] {
        let shared = ["Took the deal, but the negotiation left a mark.",
                      "Signed below his ask — he still thinks he's owed more.",
                      "Wants more. Signed anyway, and hasn't forgotten it.",
                      "Signed unhappy. He remembers how this went."]
        let specific: String = {
            switch desire {
            case .money:     return "Signed for less than he thinks he's worth, and he keeps the receipts."
            case .winning:   return "Signed for the football, not the money — and he expects the football to be worth it."
            case .statsRole: return "Signed unconvinced. He'll be counting his touches all season."
            case .loyalty:   return "Stayed out of loyalty and feels it was used against him."
            case .legacy:    return "A great career, and a last contract he thinks was beneath it."
            case .security:  return "Signed with less guaranteed than he wanted. It's on his mind."
            case .proveIt:   return "Signed short and cheap. He intends to make somebody pay for that."
            case .term:      return "Unhappy with the length. He'll be counting down the years."
            }
        }()
        return [specific] + shared
    }

    /// What the front office says when it puts an offer on the table.
    static func gmOffer(round: Int, playerFirst: String) -> [String] {
        round <= 1
            ? ["Here's where we are on \(playerFirst).",
               "Let's put something on the table.",
               "This is our opening position on \(playerFirst)."]
            : ["We've moved. Take another look.",
               "Here's a revised offer.",
               "We've had another go at it. See what you think."]
    }

    // MARK: - Pay Cut (#102)
    //
    // The one conversation in this file where the CLUB is asking for money back.
    // The pools are voice-only — no desire weave — for the same reason the
    // endings are: what a man wants out of a contract stops being the argument
    // the moment the argument is whether he keeps the one he has. The axis that
    // does matter here is his LEVERAGE, and the engine has already priced that
    // into which pool gets asked for.

    /// The front office making the ask. Blunt on purpose: dressing a pay cut up
    /// is how a club turns a bad afternoon into a grudge.
    static func payCutAsk(playerFirst: String, ctx: Ctx) -> [String] {
        ["I'll be straight with you — we're up against the cap and we need help. Would \(playerFirst) come down to \(ctx.offerPerYear)?",
         "We're asking, not telling: \(ctx.offerPerYear) this year. It keeps the roster around him intact.",
         "Cap's tight. \(ctx.offerPerYear) is the number that fixes it. What does \(playerFirst) say?",
         "This isn't about what he's worth. It's about what we can carry. \(ctx.offerPerYear)?"]
    }

    /// He signs the reduction.
    static func payCutAccept(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["Fine. \(ctx.offerPerYear), and you owe him one — I'll be collecting.",
                    "He'll do it. Not because it's fair, because he wants to win here. Remember that in March.",
                    "\(ctx.offerPerYear). Done. Don't mistake it for a habit."]
        case .professional:
            return ["We'll take \(ctx.offerPerYear). He'd rather fix the roster than argue about the difference.",
                    "That works. \(ctx.offerPerYear), and we consider the matter closed.",
                    "Agreed at \(ctx.offerPerYear). He asked me to say he's doing it for the locker room."]
        case .friendly:
            return ["Oh, he'll say yes — he already said yes before I called you. \(ctx.offerPerYear).",
                    "He loves it there. \(ctx.offerPerYear) and let's never speak of it again.",
                    "You caught him in a good mood, and he likes the group. \(ctx.offerPerYear)."]
        case .oldSchool:
            return ["A man takes a cut for a team he believes in. \(ctx.offerPerYear). He believes in yours.",
                    "\(ctx.offerPerYear). He's played long enough to know what a cap is.",
                    "He'll sign it. And he'll expect to be treated like a man who signed it."]
        }
    }

    /// He will come down — but not that far.
    static func payCutCounter(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["No. \(ctx.askPerYear) is where this ends, and you're lucky to get that.",
                    "You asked for a haircut and reached for the scalp. \(ctx.askPerYear).",
                    "\(ctx.askPerYear). Not a dollar under, and I'd stop talking now."]
        case .professional:
            return ["That's past what he can justify. \(ctx.askPerYear) is the number we'd sign.",
                    "We'll help, but within reason: \(ctx.askPerYear).",
                    "\(ctx.askPerYear) works. Below that he's better off testing the market and we both know it."]
        case .friendly:
            return ["He wants to help, he really does — but not that much. \(ctx.askPerYear)?",
                    "Meet him halfway and we're all still friends. \(ctx.askPerYear).",
                    "That's a big ask, love. \(ctx.askPerYear) and he'll sign it this afternoon."]
        case .oldSchool:
            return ["There's a cut and there's a robbery. \(ctx.askPerYear) is the cut.",
                    "He'll give you something. Not that. \(ctx.askPerYear).",
                    "\(ctx.askPerYear). I've told him not to go under it, and he listens to me."]
        }
    }

    /// The deal is the deal.
    static func payCutRefuse(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["No. You signed it, you carry it.",
                    "Your cap, your problem. He's not funding it.",
                    "Absolutely not. Go and find the money somewhere it belongs."]
        case .professional:
            return ["We're going to decline. \(ctx.playerFirst) is being paid what the market says he's worth.",
                    "No — that contract isn't the reason you're over. Look at the ones that are.",
                    "He'll play the deal he signed. That's the answer."]
        case .friendly:
            return ["I'd love to help you out. I can't ask him this one, I'm sorry.",
                    "He'd do a lot for that club. Not this. Not this year.",
                    "That's a no, and it's a kind no — he isn't your cap problem."]
        case .oldSchool:
            return ["A contract is a contract. He honored his half; honor yours.",
                    "No. And I'd think hard before asking a man like him twice.",
                    "He turned up every Sunday for that money. He keeps it."]
        }
    }

    /// "Then release him." What a star says when the ask stops being negotiable.
    static func payCutRelease(voice: AgentVoice, ctx: Ctx) -> [String] {
        switch voice {
        case .shark:
            return ["That's not a pay cut, that's a mugging. Release him. He'll have a better offer by Friday.",
                    "If that's your number, cut him. I'll have three clubs on the phone before the paperwork clears.",
                    "You've just told me what you think of him. Release him and find out what the league thinks."]
        case .professional:
            return ["If the club genuinely can't carry the contract, then release him. That's the honest version of this call.",
                    "We won't be signing that. If you need the room that badly, take the dead money and let him go.",
                    "That number isn't a negotiation. Release him — he'll be fine, and so will you."]
        case .friendly:
            return ["Oh, I don't think you meant that. If you did — let him go. Kindly, and today.",
                    "That's hurt him, that has. If it's really the number, release him and we'll part well.",
                    "He'd rather be cut than told he's worth that. Please just release him."]
        case .oldSchool:
            return ["Then release the man. Don't insult him on the way out.",
                    "Cut him. I've seen clubs do worse, but not to better people.",
                    "If that's where you are, do it properly: release him and shake his hand."]
        }
    }
}
