import SwiftUI

/// Persistent top navigation bar inspired by FM26's header chrome.
/// Displays team branding, quick-nav bookmarks, and a calendar/tasks button.
struct TopNavigationBar: View {

    let teamAbbreviation: String
    let teamName: String
    let pendingTaskCount: Int
    let onCalendarTapped: () -> Void
    var onQuitTapped: (() -> Void)?

    /// Unread mail count driving the envelope badge. 0 hides the badge.
    var unreadInboxCount: Int = 0
    /// Opens the inbox. When nil the envelope button is hidden entirely.
    var onInboxTapped: (() -> Void)?

    /// Opens Settings (#200). When nil the gear is hidden entirely — the bar
    /// stays usable in any host that has no settings destination to offer.
    ///
    /// Settings existed only behind the title screen, so changing the music
    /// level or the play clock meant abandoning the career, changing it, and
    /// loading back in. It belongs in the persistent chrome for the same
    /// reason the inbox does: it is a place you go from wherever you are.
    var onSettingsTapped: (() -> Void)?

    // MARK: - Bookmark Definitions

    struct Bookmark: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let destination: BookmarkDestination
    }

    enum BookmarkDestination {
        /// The week hub — the root of the career's navigation stack. Tapping it
        /// pops back rather than pushing (see `handleBookmarkNavigation`).
        case hub
        case roster, draft, scouting, cap, coachingStaff
        /// Trade Center (`TradeView`) — browse the other 31 rosters and
        /// propose deals. Had no primary nav entry at all before.
        case trades
    }

    /// **Seven, with the hub as one of them** (#105 wave 2, P6).
    ///
    /// The strip is for *reference destinations you return to*, and it had
    /// drifted to nine — at which point it was a second, worse main menu, and
    /// the one place the user always wants (the hub he came from) was the only
    /// thing not on it. Getting back meant hunting for a Back chevron whose
    /// depth depended on how he had arrived.
    ///
    /// The three that came off are all reachable from the hub itself, which is
    /// the rule P6 states — everything not a reference destination is reached
    /// from the hub, a task, or a process step:
    ///
    /// * **Schedule** — the hub's UPCOMING header is a link to it.
    /// * **Standings** — the hub's DIVISION header is a link to it.
    /// * **News** — the hub's MESSAGES header is a link to it.
    ///
    /// Nothing was made unreachable to shorten this list; each removal paid for
    /// itself with a route on the hub first.
    static let defaultBookmarks: [Bookmark] = [
        Bookmark(icon: "square.grid.2x2.fill", label: "Hub", destination: .hub),
        Bookmark(icon: "person.3.fill", label: "Roster", destination: .roster),
        Bookmark(icon: "person.2.fill", label: "Staff", destination: .coachingStaff),
        Bookmark(icon: "dollarsign.circle.fill", label: "Cap", destination: .cap),
        Bookmark(icon: "magnifyingglass", label: "Scouting", destination: .scouting),
        Bookmark(icon: "list.clipboard.fill", label: "Draft", destination: .draft),
        Bookmark(icon: "arrow.left.arrow.right", label: "Trades", destination: .trades),
    ]

    /// Callback when a bookmark is tapped — the shell view handles navigation.
    var onBookmarkTapped: ((BookmarkDestination) -> Void)?

    var body: some View {
        HStack(spacing: 0) {

            // MARK: Left — Team Badge
            teamBadge
                .frame(minWidth: 140, alignment: .leading)

            Spacer(minLength: 8)

            // MARK: Center — Bookmarks
            bookmarkStrip

            Spacer(minLength: 8)

            // MARK: Right — Inbox + Calendar + Settings + Quit
            HStack(spacing: 8) {
                if onInboxTapped != nil {
                    inboxButton
                }

                calendarButton

                if onSettingsTapped != nil {
                    settingsButton
                }

                Button {
                    onQuitTapped?()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Quit to main menu")
            }
            .frame(alignment: .trailing)
        }
        // 12 rather than 16: the 11 pt bookmark labels widened the strip, and
        // the bar's own edge inset is the cheapest place to find the room.
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color.backgroundPrimary)
    }

    // MARK: - Team Badge

    private var teamBadge: some View {
        HStack(spacing: 8) {
            Text(teamAbbreviation)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentGold)
                )

            Text(teamName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Team: \(teamName)")
    }

    // MARK: - Bookmark Strip

    private var bookmarkStrip: some View {
        // Seven entries at 44 pt each. Spacing stays at 8 rather than going
        // back to 12: the two widest labels came off the strip, and the width
        // that frees is spent on the team badge and the clearance around the
        // right-hand cluster instead of on gaps nobody reads.
        HStack(spacing: 8) {
            ForEach(Self.defaultBookmarks) { bookmark in
                Button {
                    onBookmarkTapped?(bookmark.destination)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: bookmark.icon)
                            .font(.system(size: 16))
                            // Fixed glyph band: SF Symbols differ in cap height
                            // (list.clipboard.fill is noticeably taller than
                            // person.3.fill), which pushed "Draft" a couple of
                            // points below its neighbours' baseline.
                            .frame(height: 18)
                        // 9 pt left a 6.5 pt cap height — legible only if you
                        // already knew what it said. At 11 pt no remaining
                        // label grows past the 44 pt touch target, so the
                        // strip's width is now exactly 7 × 44 plus its gaps.
                        Text(bookmark.label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.label)
            }
        }
    }

    // MARK: - Inbox Button

    /// Envelope + unread badge, sitting immediately left of the calendar. The
    /// inbox destination existed but had no persistent entry point, so mail
    /// (trade receipts, agent demands, owner notes) only surfaced by accident.
    private var inboxButton: some View {
        Button {
            onInboxTapped?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadInboxCount > 0 ? "envelope.badge.fill" : "envelope")
                    .font(.system(size: 18))
                    .foregroundStyle(unreadInboxCount > 0 ? Color.accentGold : Color.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())

                if unreadInboxCount > 0 {
                    // "99+", not a bare clamp. `min(count, 99)` printed an
                    // exact-looking 99 against an inbox panel reading 203 on
                    // the same screen, and against this button's own
                    // accessibility label, which has always said the true
                    // number.
                    Text(unreadInboxCount > 99 ? "99+" : "\(unreadInboxCount)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.danger))
                        .offset(x: 6, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inbox, \(unreadInboxCount) unread")
    }

    // MARK: - Settings Button

    /// Gear, sitting between the calendar and the quit door — the last stop in
    /// the "app-level" half of the cluster, before the one control that leaves
    /// the career. Deliberately `textSecondary` rather than gold: the calendar
    /// is the bar's call to action and only one thing in a cluster gets to be.
    private var settingsButton: some View {
        Button {
            onSettingsTapped?()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: DSType.Size.title3))
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Calendar Button

    private var calendarButton: some View {
        Button(action: onCalendarTapped) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: DSType.Size.title2))
                    .foregroundStyle(Color.accentGold)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())

                if pendingTaskCount > 0 {
                    Text("\(pendingTaskCount)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.danger)
                        )
                        .offset(x: 6, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendar and tasks, \(pendingTaskCount) pending")
    }
}

#Preview {
    VStack(spacing: 0) {
        TopNavigationBar(
            teamAbbreviation: "KC",
            teamName: "Kansas City Stockyards",
            pendingTaskCount: 3,
            onCalendarTapped: {},
            unreadInboxCount: 2,
            onInboxTapped: {},
            onSettingsTapped: {}
        )
        Spacer()
    }
    .background(Color.backgroundPrimary)
}
