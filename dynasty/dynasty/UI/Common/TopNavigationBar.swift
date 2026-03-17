import SwiftUI

/// Persistent top navigation bar inspired by FM26's header chrome.
/// Displays team branding, quick-nav bookmarks, and a calendar/tasks button.
struct TopNavigationBar: View {

    let teamAbbreviation: String
    let teamName: String
    let pendingTaskCount: Int
    let onCalendarTapped: () -> Void
    var onQuitTapped: (() -> Void)?

    // MARK: - Bookmark Definitions

    struct Bookmark: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let destination: BookmarkDestination
    }

    enum BookmarkDestination {
        case roster, schedule, standings, draft, scouting, cap
    }

    static let defaultBookmarks: [Bookmark] = [
        Bookmark(icon: "person.3.fill", label: "Roster", destination: .roster),
        Bookmark(icon: "calendar", label: "Schedule", destination: .schedule),
        Bookmark(icon: "list.number", label: "Standings", destination: .standings),
        Bookmark(icon: "list.clipboard.fill", label: "Draft", destination: .draft),
        Bookmark(icon: "magnifyingglass", label: "Scouting", destination: .scouting),
        Bookmark(icon: "dollarsign.circle.fill", label: "Cap", destination: .cap),
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

            // MARK: Right — Calendar + Quit
            HStack(spacing: 12) {
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
        .padding(.horizontal, 16)
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
        HStack(spacing: 12) {
            ForEach(Self.defaultBookmarks) { bookmark in
                Button {
                    onBookmarkTapped?(bookmark.destination)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: bookmark.icon)
                            .font(.system(size: 16))
                        Text(bookmark.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 48, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.label)
            }
        }
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
