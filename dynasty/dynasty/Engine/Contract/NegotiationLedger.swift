import Foundation

// MARK: - Negotiation History Ledger (market-realism wave)

/// What the league remembers about how this GM negotiates.
///
/// **Why a ledger and not a flag.** Every other lever on an agent's ask is a
/// snapshot of the present — the player's rating, his mood, the club's record.
/// None of them can express the one thing that actually makes a real front
/// office cheap or expensive to deal with: *history*. A GM who opens every
/// conversation at half price gets a reputation for it, and the next agent
/// through the door prices that in before he sits down. A GM who pays fairly
/// and closes quickly gets the opposite, and it is worth real money to him.
///
/// So this is a per-career counter of the four events an agent community would
/// actually gossip about, and one derived number —
/// ``hardballReputation`` — that ``ContractNegotiationEngine`` folds into the
/// GM factor. It is deliberately slow: a single insult is worth well under one
/// percent, and it takes a pattern to reach the ceiling.
///
/// **Storage.** careerID-scoped `UserDefaults` through `CareerScopedDefaults`,
/// the same shape as `NegotiationLockRegistry` and `ContractIncentiveRegistry`,
/// with inline defaults so a save that has never negotiated reads as a clean
/// sheet rather than as missing data. Listed in `CareerScopedDefaults.keys` so
/// deleting a career takes its reputation with it. No SwiftData migration.
///
/// **Determinism.** Nothing here rolls a die. The same sequence of negotiation
/// outcomes always produces the same reputation, which is what makes the effect
/// learnable: a player who stops lowballing watches the number come back down.
enum NegotiationLedger {

    // MARK: - Record

    /// The counters behind one career's negotiating reputation.
    struct Record: Codable, Equatable {
        /// Offers graded `.insulted` — at least 25 % under the agent's floor.
        var insults: Int = 0
        /// Talks a lowball killed outright for the offseason.
        var breakOffs: Int = 0
        /// Conversations the agent ended by walking.
        var walkAways: Int = 0
        /// Deals closed while the agent was still in an `.eager` or
        /// `.professional` frame — a negotiation that did not leave a mark.
        var smoothSignings: Int = 0

        /// Deals closed after the conversation had already turned. Counted
        /// separately from `smoothSignings` because signing a man you insulted
        /// does not undo the insult — it just means he needed the job.
        var begrudgingSignings: Int = 0

        static let empty = Record()

        /// Signed weight of this career's negotiating history.
        ///
        /// Positive is a hardball reputation (agents ask for more); negative is
        /// a reputation for straight dealing (they ask for slightly less). The
        /// weights say what each event is worth in the room: breaking talks off
        /// is twice an insult because the whole league hears about it, a walk is
        /// half of one because agents walk for their own reasons too, and a
        /// clean signing is worth half an insult in the other direction so that
        /// a reputation can be repaired but never *quickly*.
        var hardballScore: Double {
            Double(insults) * 1.0
                + Double(breakOffs) * 2.0
                + Double(walkAways) * 0.5
                + Double(begrudgingSignings) * 0.25
                - Double(smoothSignings) * 0.5
        }
    }

    // MARK: - Tuning

    /// What one point of `hardballScore` is worth on an agent's ask.
    ///
    /// 0.6 % per point, so it takes six insults with nothing to offset them to
    /// reach the +3.6 % that a player would first notice, and ten to hit the
    /// ceiling. That slowness is the design: a reputation the user can acquire
    /// in one conversation is a punishment, not a reputation.
    static let pointValue = 0.006

    /// Hard bounds on the reputation term. The upside is capped at +6 % because
    /// the GM factor as a whole is capped at +15 % and the other four
    /// components have to be able to matter; the downside at −3 % because no
    /// front office ever negotiated its way to a large permanent discount.
    static let bounds: ClosedRange<Double> = -0.03 ... 0.06

    // MARK: - Derived Reputation

    /// The multiplier term this career's negotiating history contributes to an
    /// agent's ask. `0` for a save that has never had a contract conversation.
    static func hardballReputation(_ record: Record = current()) -> Double {
        let raw = record.hardballScore * pointValue
        return Swift.min(bounds.upperBound, Swift.max(bounds.lowerBound, raw))
    }

    // MARK: - Storage

    /// Base key — namespaced per save through `CareerScopedDefaults.scopedKey`.
    /// Listed in `CareerScopedDefaults.keys`; never read bare (see the note on
    /// `NegotiationLockRegistry.baseKey` for what a bare read costs).
    static let defaultsKey = "negotiationHistoryLedger"

    private static var key: String { CareerScopedDefaults.scopedKey(defaultsKey) }

    /// This save's ledger — an empty record when nothing has been written yet.
    static func current() -> Record {
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return .empty }
        return record
    }

    /// The ledger for an explicit career, for surfaces that are not looking at
    /// the active save.
    static func record(careerID: UUID) -> Record {
        let scoped = CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        guard let data = UserDefaults.standard.data(forKey: scoped),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return .empty }
        return record
    }

    private static func write(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Events
    //
    // WHO CALLS THESE: `ContractNegotiationEngine.respond` and nothing else.
    // It is the single place an offer is graded, so it is the single place the
    // history is written — a chat layer that also recorded its own close would
    // count every negotiation twice and double the reputation the user earns.
    // `respond(recordToLedger:)` is the switch for callers that must not write
    // (previews, sweeps, the balance harness).

    /// An offer landed at least 25 % under the agent's floor.
    static func recordInsult() {
        var r = current(); r.insults += 1; write(r)
    }

    /// A lowball ended talks for the offseason.
    static func recordBreakOff() {
        var r = current(); r.breakOffs += 1; write(r)
    }

    /// The agent walked away from the table.
    static func recordWalkAway() {
        var r = current(); r.walkAways += 1; write(r)
    }

    /// A deal closed. `tone` is the frame the agent was in when he signed —
    /// `.eager` / `.professional` is a clean close, anything else is one the
    /// player remembers.
    static func recordSigning(tone: AgentToneKey) {
        var r = current()
        switch tone {
        case .eager, .professional: r.smoothSignings += 1
        default:                    r.begrudgingSignings += 1
        }
        write(r)
    }

    /// Wipes the ledger — a new career, or a debug reset.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
