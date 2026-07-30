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

    // MARK: - Bookmark Definitions

    struct Bookmark: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let destination: BookmarkDestination
    }

    enum BookmarkDestination {
        case roster, schedule, standings, draft, scouting, cap, coachingStaff
        /// League news feed (`NewsView`) — previously reachable only from the
        /// round-recap sheet, which meant trade/signing headlines were
        /// effectively invisible between games.
        case news
        /// Trade Center (`TradeView`) — browse the other 31 rosters and
        /// propose deals. Had no primary nav entry at all before.
        case trades
    }

    static let defaultBookmarks: [Bookmark] = [
        Bookmark(icon: "person.3.fill", label: "Roster", destination: .roster),
        Bookmark(icon: "person.2.fill", label: "Staff", destination: .coachingStaff),
        Bookmark(icon: "calendar", label: "Schedule", destination: .schedule),
        Bookmark(icon: "list.number", label: "Standings", destination: .standings),
        Bookmark(icon: "list.clipboard.fill", label: "Draft", destination: .draft),
        Bookmark(icon: "magnifyingglass", label: "Scouting", destination: .scouting),
        Bookmark(icon: "dollarsign.circle.fill", label: "Cap", destination: .cap),
        Bookmark(icon: "arrow.left.arrow.right", label: "Trades", destination: .trades),
        Bookmark(icon: "newspaper.fill", label: "News", destination: .news),
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

            // MARK: Right — Inbox + Calendar + Quit
            HStack(spacing: 8) {
                if onInboxTapped != nil {
                    inboxButton
                }

                calendarButton

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
        // 9 entries at 44 pt each — spacing trimmed from 12 to 8 so News and
        // Trades fit alongside the original seven in iPad portrait without the
        // strip crowding the team badge.
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
                        // already knew what it said. 11 pt costs the strip
                        // ~15 pt of total width (only "Standings" and
                        // "Schedule" grow past the 44 pt touch target), which
                        // the trimmed 12 pt bar padding below pays for.
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
                    Text("\(min(unreadInboxCount, 99))")
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

    // MARK: - Calendar Button

    private var calendarButton: some View {
        Button(action: onCalendarTapped) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
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
            teamName: "Kansas City Chiefs",
            pendingTaskCount: 3,
            onCalendarTapped: {}
        )
        Spacer()
    }
    .background(Color.backgroundPrimary)
}
