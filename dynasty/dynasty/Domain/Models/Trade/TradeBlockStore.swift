import Combine
import Foundation

// MARK: - TradeBlockStore
//
// F-58, the half that remembers. The user's own list of the men he is willing to
// move.
//
// ## Why this is a user note and not engine state
//
// A trade block is a front office's shortlist, and this one is exactly that: it
// is the same kind of object as the roster notes, the prospect watchlist and the
// custom board — a thing the user wrote down, career-scoped, purged with the
// save. It carries no engine consequence, and the copy on every surface that
// shows it says so in as many words.
//
// **It deliberately does NOT write `TradeRequestRegistry`.** That registry means
// something specific and different: the PLAYER has publicly demanded a trade,
// and since F-53 `shoppingTarget` reads it to raise both the number and the
// aggressiveness of incoming calls. Routing the user's shortlist through it
// would have bought real AI behaviour at the price of a lie about who asked —
// a club listing a backup tight end is not that man demanding out, and the
// news, the locker room and the negotiation copy would all have said he did.
//
// ## The engine seam, named rather than taken
//
// The honest version of "the block makes the phone ring" is one line in
// `shoppingTarget`, which already reads `TradeRequestRegistry.hasStandingRequest`
// for exactly this shape of signal. A `TradeBlockStore.isListed(_:)` check
// alongside it — weighted lower than a public demand, because a quiet shortlist
// is not a public one — is the whole change. `Engine/**` is another agent's this
// wave, so the seam is named here and left alone.
//
// Until that lands, no surface in this app claims the block changes the market.

/// The user's shortlist of players he is willing to move.
///
/// Career-scoped `UserDefaults`, keyed per access rather than cached, so a
/// career switch inside one launch is picked up without anyone remembering to
/// notify the store — the same shape as `UserProspectGradeStore`.
final class TradeBlockStore: ObservableObject {

    static let shared = TradeBlockStore()
    private init() {}

    /// Listed in `CareerScopedDefaults.keys`, so a deleted save takes its block
    /// with it and a new career never opens with somebody else's shortlist.
    static let defaultsKey = "tradeBlock"

    /// A block is a shortlist, not a fire sale. The cap exists so the screen
    /// stays a decision — a "block" holding twenty men is a roster.
    static let maxListed = 8

    private var key: String {
        guard let careerID = WeekAdvancer.activeCareerID else { return Self.defaultsKey }
        return CareerScopedDefaults.key(Self.defaultsKey, careerID: careerID)
    }

    /// Ordered: the user's own priority, oldest listing first.
    private var storedIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    // MARK: - Reads

    var listedIDs: [UUID] { storedIDs.compactMap(UUID.init(uuidString:)) }

    var count: Int { storedIDs.count }

    var isFull: Bool { storedIDs.count >= Self.maxListed }

    func isListed(_ playerID: UUID) -> Bool {
        storedIDs.contains(playerID.uuidString)
    }

    // MARK: - Writes

    /// Adds a player to the block. No-op when he is already on it or the block
    /// is full.
    func list(_ playerID: UUID) {
        var ids = storedIDs
        guard !ids.contains(playerID.uuidString), ids.count < Self.maxListed else { return }
        ids.append(playerID.uuidString)
        storedIDs = ids
        objectWillChange.send()
        CareerScopedDefaultsStore.shared.notifyChanged()
    }

    func unlist(_ playerID: UUID) {
        var ids = storedIDs
        guard let index = ids.firstIndex(of: playerID.uuidString) else { return }
        ids.remove(at: index)
        storedIDs = ids
        objectWillChange.send()
        CareerScopedDefaultsStore.shared.notifyChanged()
    }

    @discardableResult
    func toggle(_ playerID: UUID) -> Bool {
        if isListed(playerID) {
            unlist(playerID)
            return false
        }
        list(playerID)
        return isListed(playerID)
    }

    /// Drops anyone who is no longer on the user's roster.
    ///
    /// A listed man who was traded, released or retired is a stale row, and the
    /// block screen would otherwise print him forever. Called when the block is
    /// opened rather than on a timer: the screen is the only place it matters.
    func prune(toRosterIDs rosterIDs: Set<UUID>) {
        let kept = storedIDs.filter { raw in
            guard let id = UUID(uuidString: raw) else { return false }
            return rosterIDs.contains(id)
        }
        guard kept.count != storedIDs.count else { return }
        storedIDs = kept
        objectWillChange.send()
    }
}
