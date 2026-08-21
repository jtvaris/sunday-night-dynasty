import SwiftUI
import Combine

// MARK: - DraftRoomChatterLog — the room remembers what was said (#198 (1))
//
// `DraftBroadcastRail` is the only place the four voices of the room are ever
// printed, and it prints each of them for **1.6 to 2.6 seconds** before the card
// fades. That is the right dwell for an ambient overlay and the wrong lifetime
// for the most personal writing in the game: the owner's verdict on a reach, the
// locker room's read on a pick that blocks somebody's snaps, the fans' line
// about a name they had never heard of. A user who looks down at the board — the
// surface the night is actually played on — loses them permanently, and there
// was no second home for any of it.
//
// Meanwhile `WarRoomPanel`'s "Scout Chatter" card was **one hardcoded sentence**
// computed off `lastPickResult`, rewritten in place on every card, with no
// history and nothing any actor had actually said in it.
//
// This is the join: the rail keeps its dwell, and every beat it retires is
// appended here on the way out. The war room's chatter card is then the room's
// running transcript — the same voices, the same SF Symbols, the same tints,
// with the newest line on top.
//
// ## It is presentation, and it is deliberately not persisted
//
// Nothing in here is state the engine owns or the save file needs. The log is a
// view-model on `DraftDayView` (`@StateObject`), handed to the two views that
// write and read it through `.environmentObject`, and it dies with the room. A
// draft night's chatter is theatre about facts that are all still on the board
// afterwards — the picks, the grades, the reputation deltas — so there is
// nothing to reconstruct and no `careerID` to stamp.
//
// ## Capacity
//
// The card shows ``visibleCount`` lines; the log keeps ``capacity`` so that a
// four-voice cluster arriving in one instant cannot push the previous pick's
// quartet out of the buffer before it has been on screen at all. Newest first,
// because a feed nobody scrolls has to lead with the news.

@MainActor
final class DraftRoomChatterLog: ObservableObject {

    /// One thing somebody said, flattened out of whatever kind of beat carried
    /// it.
    ///
    /// `icon` and `tint` are copied from the beat rather than re-derived: the
    /// whole point of the transcript is that a line reads the same in the war
    /// room as it did on the rail, and a second mapping from actor to symbol is
    /// how the two drift apart.
    struct Line: Identifiable, Equatable {
        /// Monotonic, assigned by the log — see ``DraftRoomChatterLog/append``.
        /// A beat's own key is a dedup token for the RAIL's queue, and two
        /// different picks can legitimately produce the identical sentence
        /// ("Fans are quiet on this one"), so the transcript cannot use it as
        /// an identity or `ForEach` collapses the repeat.
        let id: Int
        /// SF Symbol. Never emoji (§2.12).
        let icon: String
        /// Who spoke: `Owner`, `Media`, `Locker room`, `Fans` — or, for a
        /// broadcast beat, the beat's own eyebrow ("Steal of the draft").
        let voice: String
        let message: String
        /// The mechanical consequence, when the line had one.
        let delta: Int?
        /// The rail's accent for this line: green for a good outcome, orange
        /// for a bad one, blue for information.
        let tint: Color
    }

    /// How many lines the war room's card prints. Six is what fits the drawer's
    /// chatter card without pushing the trade radar and the capital ledger under
    /// the fold — the defect the whole panel was re-proportioned for in #194-v2.
    static let visibleCount = 6

    /// How many the log keeps. Four voices per pick, so this is one pick's
    /// quartet on screen and five picks' worth behind it.
    private static let capacity = 24

    @Published private(set) var lines: [Line] = []

    private var sequence = 0

    var isEmpty: Bool { lines.isEmpty }

    /// The newest ``visibleCount`` lines, newest first.
    var visibleLines: [Line] {
        Array(lines.prefix(Self.visibleCount))
    }

    /// Appends one line. Newest first, oldest dropped past ``capacity``.
    func append(icon: String, voice: String, message: String, delta: Int?, tint: Color) {
        guard !message.isEmpty else { return }
        sequence += 1
        lines.insert(
            Line(id: sequence, icon: icon, voice: voice, message: message, delta: delta, tint: tint),
            at: 0
        )
        if lines.count > Self.capacity {
            lines.removeLast(lines.count - Self.capacity)
        }
    }
}
