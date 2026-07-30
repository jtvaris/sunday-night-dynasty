import Foundation

// MARK: - Trade Negotiation Thread (Wave 3 — `docs/TRADE_OVERHAUL_PLAN.md` §6)
//
// The persisted state of ONE conversation with ONE GM.
//
// WHY a thread and not another alert: before Wave 3 a user proposal was a
// single round-trip — tap Propose, read a one-line verdict in an alert, and the
// counter silently overwrote the builder with no record that a conversation had
// happened at all (plan finding S7). The contract stack already had the answer
// in `ContractNegotiationEngine` / `ContractNegotiationView`: a transcript, a
// round counter against the other side's patience, offer snapshots inside the
// bubbles, and a break-off that means something. This is that template ported
// to trades, with the Wave 2 market as the brain — `TradeValueEngine.respond`
// drives every AI turn, so the transcript and the executed outcome are the same
// numbers (G7).
//
// PLACEMENT NOTE: this is a pure Codable domain model living under `UI/Contracts`
// because the Wave 3 slice owns that folder. HANDOFF: it belongs next to
// `TradeProposal` (`Engine/Contract/TradeEngine.swift`) or in `Domain/Models`,
// and moving it is a file move with no code change.

/// Who said it. Raw-string backed so the transcript survives enum edits, the
/// same migration-safety rule `TradeRecord.phaseRaw` follows.
enum TradeThreadSender: String, Codable {
    /// The AI club's general manager.
    case gm
    /// The user's front office.
    case you
    /// Neutral narration — "deal agreed", "talks broke off", "offer expired".
    case system
}

/// Where a conversation stands. Only `.open` threads accept another round.
enum TradeThreadStatus: String, Codable {
    case open
    /// A deal was struck and executed.
    case agreed
    /// The user walked away.
    case withdrawn
    /// The GM stopped answering — the Wave 2 talk lock (`TradeTalkRegistry`).
    case brokenOff
    /// The window closed (deadline / new league year) with the deal unsigned.
    case expired
}

/// One bubble in the transcript.
struct TradeThreadMessage: Codable, Identifiable {
    let id: UUID
    let sender: TradeThreadSender
    let text: String
    /// Snapshot of the package as it stood when this line was said, ALWAYS from
    /// the user's perspective (`offeringTeamID` is the user's team). Storing the
    /// snapshot rather than re-deriving it is the whole point: a transcript that
    /// re-renders today's package next to last week's sentence is a lie.
    let proposal: TradeProposal?
    /// Negotiation round this line belongs to (0 = opening).
    let round: Int

    init(
        id: UUID = UUID(),
        sender: TradeThreadSender,
        text: String,
        proposal: TradeProposal? = nil,
        round: Int
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.proposal = proposal
        self.round = round
    }
}

/// One live conversation with one GM, persisted on `Career` so it survives the
/// view, the app launch, and the week advance (plan §6 Wave 3.2).
struct TradeNegotiationThread: Codable, Identifiable {
    let id: UUID
    /// The AI club on the other end.
    let partnerTeamID: UUID
    /// League year the thread opened in. A thread never crosses a league year:
    /// `TradeTalkRegistry` resets in February and the assets have all moved.
    let season: Int
    /// Week the first line was said.
    let openedWeek: Int
    /// Week of the most recent line — drives the "gone quiet" copy.
    var lastActivityWeek: Int
    /// Completed rounds. Compared against `GMPersona.maxRounds` (exposed as
    /// `TradeValueEngine.GMIdentity.patience`) for the patience meter.
    var round: Int
    var messages: [TradeThreadMessage]
    /// The package on the table right now, from the user's perspective.
    var proposal: TradeProposal
    /// The AI's standing counter, if it made one — what "Accept" accepts.
    var pendingCounter: TradeProposal?
    var status: TradeThreadStatus
    /// True when the AI picked up the phone first (an inbox offer the user
    /// opened) rather than the user building a package.
    let startedByAI: Bool
    /// The `career.pendingTradeOffers` row this thread grew out of, so accepting
    /// or declining here prunes the same offer from the Trade Center.
    let sourceOfferID: UUID?

    init(
        id: UUID = UUID(),
        partnerTeamID: UUID,
        season: Int,
        openedWeek: Int,
        round: Int = 0,
        messages: [TradeThreadMessage] = [],
        proposal: TradeProposal,
        pendingCounter: TradeProposal? = nil,
        status: TradeThreadStatus = .open,
        startedByAI: Bool,
        sourceOfferID: UUID? = nil
    ) {
        self.id = id
        self.partnerTeamID = partnerTeamID
        self.season = season
        self.openedWeek = openedWeek
        self.lastActivityWeek = openedWeek
        self.round = round
        self.messages = messages
        self.proposal = proposal
        self.pendingCounter = pendingCounter
        self.status = status
        self.startedByAI = startedByAI
        self.sourceOfferID = sourceOfferID
    }

    var isOpen: Bool { status == .open }

    /// Newest first is how the Trade Center lists threads.
    var lastLine: String { messages.last?.text ?? "" }
}
