import SwiftUI
import SwiftData

// MARK: - InboxView
//
// Wave 5b. The inbox on the list standard: `DSLensTabs` for the filter strip,
// `DSListRow` for the message, `DSStatusPill` for "action required",
// `DSEmptyState` for the empty tray (UI_REDESIGN_VISION §2.2 / §2.3 / §2.7).
//
// Three things this conversion fixes, all of them named by the audit:
//
//  1. **A fifth tab-bar implementation is gone.** The filter chips were a
//     hand-rolled capsule strip at 36 pt with a blue count bubble — one of the
//     five independent tab bars §0 counted, and under the 44 pt target floor
//     §2.12 says has no exceptions. `DSLensTabs` is the one control style, and
//     the unread count folds into the label so the strip carries the same fact
//     with one element instead of two.
//  2. **The row reserves its slots.** The unread dot used to collapse to
//     `Color.clear` and the ACTION chip appeared only on the rows that had one,
//     so the leading edge and the trailing column both jittered down the list.
//     Both slots are now drawn on every line (§2.2's fixed-slot rule) — the
//     user reads a column of marks rather than a ragged edge.
//  3. **The 0.35 s navigation hack is gone.** Tapping a message's action used
//     to dismiss the sheet and then fire the navigation off a timer, which is
//     exactly the sequencing hack §2.8 calls out. The destination is now parked
//     and replayed from `.sheet(onDismiss:)`, so the handoff is ordered by
//     SwiftUI rather than by a deadline.
//
// One `.sheet(item:)` on this view, as the house rule requires.

struct InboxView: View {

    let career: Career
    @Binding var messages: [InboxMessage]
    var onNavigate: ((TaskDestination) -> Void)?

    @State private var activeFilter: InboxFilter = .all
    @State private var selectedMessage: InboxMessage?
    /// Where the dismissed message wanted to send the user. Replayed from
    /// `onDismiss` instead of from a 0.35 s timer.
    @State private var pendingDestination: TaskDestination?

    private var filteredMessages: [InboxMessage] {
        // Newest first, then sort by importance bucket:
        // 1) Action Required (unread first), 2) Unread, 3) Read
        let chronological = Array(messages.reversed())
        let filtered = chronological.filter { activeFilter.matches($0) }
        return filtered.enumerated()
            .sorted { lhs, rhs in
                let l = sortRank(for: lhs.element)
                let r = sortRank(for: rhs.element)
                if l != r { return l < r }
                return lhs.offset < rhs.offset // preserve newest-first within bucket
            }
            .map { $0.element }
    }

    private func sortRank(for message: InboxMessage) -> Int {
        // A pinned letter outranks everything: pinning is the user overriding
        // the tray's own idea of what matters.
        if message.isPinned                              { return 0 }
        if message.isActionOutstanding && !message.isRead { return 1 }
        if message.isActionOutstanding                    { return 2 }
        if !message.isRead                                { return 3 }
        return 4
    }

    private var unreadCount: Int {
        messages.filter { !$0.isRead && !$0.isArchived }.count
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                messageListContent
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .foregroundStyle(Color.accentBlue)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                bulkActionsMenu
            }
        }
        // The ONE modal slot on this view. The destination handoff runs in
        // `onDismiss`, so the inbox is already gone before the shell navigates —
        // no timer, no race.
        .sheet(item: $selectedMessage, onDismiss: {
            if let destination = pendingDestination {
                pendingDestination = nil
                onNavigate?(destination)
            }
        }) { message in
            NavigationStack {
                MessageDetailView(
                    message: message,
                    onNavigate: { destination in
                        pendingDestination = destination
                        selectedMessage = nil
                    },
                    onAppear: {
                        markAsRead(messageID: message.id)
                    },
                    onMarkHandled: {
                        markActionHandled(messageID: message.id)
                    }
                )
            }
        }
    }

    private func markAsRead(messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        if !messages[index].isRead {
            messages[index].isRead = true
        }
    }

    // MARK: - Per-message state

    private func mutate(_ messageID: UUID, _ change: (inout InboxMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&messages[index])
    }

    /// Clears an Action Required letter. Reading it never did — that only ever
    /// flipped `isRead`, so the red chip outlived the job it was asking for.
    private func markActionHandled(messageID: UUID) {
        mutate(messageID) { message in
            guard message.actionRequired, !message.actionCompleted else { return }
            message.actionCompleted = true
            message.isRead = true
        }
    }

    private func togglePinned(messageID: UUID) {
        mutate(messageID) { $0.isPinned.toggle() }
    }

    private func toggleArchived(messageID: UUID) {
        mutate(messageID) { message in
            message.isArchived.toggle()
            // An archived letter is put away, not held up.
            if message.isArchived { message.isPinned = false }
        }
    }

    private func toggleRead(messageID: UUID) {
        mutate(messageID) { $0.isRead.toggle() }
    }

    private func delete(messageID: UUID) {
        messages.removeAll { $0.id == messageID }
    }

    // MARK: - Bulk actions

    /// The tray had exactly one toolbar item — a read-only unread count — so a
    /// season's worth of mail could only be cleared one letter at a time.
    private var bulkActionsMenu: some View {
        Menu {
            Button {
                markAllRead()
            } label: {
                Label("Mark all as read", systemImage: "envelope.open")
            }
            .disabled(unreadCount == 0)

            Button {
                archiveRead()
            } label: {
                Label("Archive read messages", systemImage: "archivebox")
            }
            .disabled(archivableCount == 0)

            Divider()

            Button(role: .destructive) {
                deleteArchived()
            } label: {
                Label("Delete archived", systemImage: "trash")
            }
            .disabled(archivedCount == 0)
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.accentGold)
        }
        .accessibilityLabel("Inbox actions")
    }

    /// Read, not archived, and not still asking for something — an outstanding
    /// Action Required letter is never swept up by a bulk tidy.
    private var archivableCount: Int {
        messages.filter { $0.isRead && !$0.isArchived && !$0.isActionOutstanding && !$0.isPinned }.count
    }

    private var archivedCount: Int {
        messages.filter(\.isArchived).count
    }

    private func markAllRead() {
        for index in messages.indices where !messages[index].isRead {
            messages[index].isRead = true
        }
    }

    private func archiveRead() {
        for index in messages.indices
        where messages[index].isRead
            && !messages[index].isArchived
            && !messages[index].isActionOutstanding
            && !messages[index].isPinned {
            messages[index].isArchived = true
        }
    }

    private func deleteArchived() {
        messages.removeAll(where: \.isArchived)
    }

    // MARK: - Filter strip (§2.2)

    /// The count travels in the label rather than in a second bubble: a lens
    /// capsule is one control with one reading, and the bubble was the only
    /// thing in the strip painting `.white` on an accent fill.
    private func filterLabel(_ filter: InboxFilter) -> String {
        let unread = messages.filter { !$0.isRead && filter.matches($0) }.count
        return unread > 0 ? "\(filter.label) \(unread)" : filter.label
    }

    private var filterBar: some View {
        DSLensTabs(
            selection: $activeFilter,
            lenses: InboxFilter.allCases,
            label: filterLabel,
            icon: { filter in
                switch filter {
                case .all:            return "tray.full"
                case .actionRequired: return "exclamationmark.circle"
                case .unread:         return "envelope.badge"
                case .archived:       return "archivebox"
                }
            },
            title: "Filter"
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        // Same measure as the message list, so "All" starts on the same
        // vertical as the message rows rather than out at the screen edge.
        // The band behind it still spans full width.
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.surfaceBorder)
        }
    }

    // MARK: - Message list

    private var messageListContent: some View {
        Group {
            if filteredMessages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(filteredMessages) { message in
                            messageRow(message)
                        }
                    }
                    .padding(DSSpacing.md)
                    .frame(maxWidth: DSLayout.contentMeasure)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Width of the leading slot: the reserved unread dot plus the sender disc.
    private static let senderSlot: CGFloat = 8 + DSSpacing.xs + 36

    private func messageRow(_ message: InboxMessage) -> some View {
        Button {
            // Open the detail sheet — MessageDetailView reports `onAppear`
            // which marks the message as read in the source array.
            selectedMessage = message
        } label: {
            DSListRow(
                // A message carries a two-line preview under a subject line, so
                // it is a card stack, not a scan row (P3).
                density: .study,
                portraitWidth: Self.senderSlot,
                affordance: .disclosure,
                portrait: { senderSlot(message) },
                identity: { identity(message) },
                columns: { actionSlot(message) }
            )
            .padding(.horizontal, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(rowFill(for: message))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(
                        rowBorderColor(for: message),
                        lineWidth: message.isActionOutstanding ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(message) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel(message))
        .accessibilityHint("Opens the message")
    }

    /// The row's gestures. A `LazyVStack` is not a `List`, so `swipeActions` is
    /// unavailable here — a long press is the affordance that works in both the
    /// stack and under VoiceOver.
    @ViewBuilder
    private func rowMenu(_ message: InboxMessage) -> some View {
        Button {
            togglePinned(messageID: message.id)
        } label: {
            Label(
                message.isPinned ? "Unpin" : "Pin to top",
                systemImage: message.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            toggleRead(messageID: message.id)
        } label: {
            Label(
                message.isRead ? "Mark as unread" : "Mark as read",
                systemImage: message.isRead ? "envelope.badge" : "envelope.open"
            )
        }

        if message.isActionOutstanding {
            Button {
                markActionHandled(messageID: message.id)
            } label: {
                Label("Mark as handled", systemImage: "checkmark.circle")
            }
        }

        Divider()

        Button {
            toggleArchived(messageID: message.id)
        } label: {
            Label(
                message.isArchived ? "Move to inbox" : "Archive",
                systemImage: message.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Button(role: .destructive) {
            delete(messageID: message.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// The reserved unread mark plus the sender's disc. The dot's 8 pt is drawn
    /// on every row, read or unread — a slot that collapses is the jitter §2.2
    /// names.
    private func senderSlot(_ message: InboxMessage) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.accentBlue)
                .frame(width: 8, height: 8)
            Image(systemName: message.sender.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(iconColor(for: message.sender))
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconColor(for: message.sender).opacity(0.15)))
        }
    }

    private func identity(_ message: InboxMessage) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                if message.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                }
                Text(message.sender.displayName.uppercased())
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Text("\u{00B7}")
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .foregroundStyle(Color.textTertiary)
                // Relative game time, not the phase banner. Every row used to
                // print the same "Offseason - The Combine, 2026" because that is
                // all the model carried; it now carries the moment.
                Text(timeLabel(message))
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(message.subject)
                .font(DSType.text(DSType.Size.body, message.isRead ? .regular : .bold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Message bodies open with a salutation on its own line
            // ("Coach,\n\n…"), so a raw single-line preview rendered as the
            // useless "Coach,…". Flatten the newlines first and allow two lines
            // so the preview carries real content.
            Text(previewText(message))
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, DSSpacing.xs)
    }

    /// The trailing state column. Always the same width, so the subject lines
    /// on an action row and a plain row end on the same vertical.
    private func actionSlot(_ message: InboxMessage) -> some View {
        Group {
            if message.isActionOutstanding {
                DSStatusPill(label: "Action", tone: .bad, showsDot: false)
            } else if message.actionRequired {
                DSStatusPill(label: "Handled", tone: .ok, showsDot: false)
            } else {
                Color.clear
            }
        }
        .dsColumn(DSListColumn.state)
    }

    /// Relative game time for the row, read against where the career is now.
    private func timeLabel(_ message: InboxMessage) -> String {
        message.timeLabel(
            currentWeek: career.currentWeek,
            currentSeason: career.currentSeason,
            currentPhase: career.currentPhase
        )
    }

    private func previewText(_ message: InboxMessage) -> String {
        message.body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func spokenLabel(_ message: InboxMessage) -> String {
        [
            message.isRead ? nil : "Unread",
            message.isPinned ? "Pinned" : nil,
            message.isActionOutstanding ? "Action required" : nil,
            message.actionRequired && message.actionCompleted ? "Action handled" : nil,
            "\(message.sender.displayName), \(timeLabel(message))",
            message.subject
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    private func rowFill(for message: InboxMessage) -> Color {
        if message.isActionOutstanding {
            // Subtle red tint so Action Required messages clearly pop above the rest.
            return Color.danger.opacity(0.12)
        }
        return message.isRead ? Color.backgroundSecondary : Color.backgroundSecondary.opacity(0.9)
    }

    private func rowBorderColor(for message: InboxMessage) -> Color {
        if message.isActionOutstanding { return Color.danger.opacity(0.7) }
        if message.isPinned { return Color.accentGold.opacity(0.5) }
        return Color.surfaceBorder
    }

    // MARK: - Empty (§2.7)

    /// Beat three is the filter, not the mailbox: "no messages" is a different
    /// problem from "no messages *matching Action Required*", and only the
    /// second one has a button that fixes it.
    private var emptyState: some View {
        VStack {
            Spacer(minLength: 0)
            DSEmptyState(
                icon: "tray",
                title: activeFilter == .all ? "No messages" : "Nothing under \(activeFilter.label)",
                message: activeFilter == .all
                    ? "Messages from your staff, owner, scouts and media land here as the season runs."
                    : "\(messages.count) message\(messages.count == 1 ? "" : "s") in the tray, none of them matching this filter.",
                actions: activeFilter == .all
                    ? []
                    : [.init(title: "Show all messages", systemImage: "tray.full", isPrimary: true) {
                        withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .all }
                    }]
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func iconColor(for sender: MessageSender) -> Color {
        switch sender {
        case .owner:                    return Color.accentGold
        case .offensiveCoordinator:     return Color.accentBlue
        case .defensiveCoordinator:     return Color.danger
        case .scout:                    return Color.success
        case .media:                    return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .leagueOffice:             return Color.warning
        case .playerAgent:              return Color.textSecondary
        case .developmentStaff:         return Color.eliteGreen
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewMessages: [InboxMessage] = [
        InboxMessage(
            sender: .owner(name: "Jerry Jones"),
            subject: "Welcome -- Roster Assessment Needed",
            body: "Coach, I'd like your assessment of our current roster...",
            date: "Offseason - Coaching Changes, 2026",
            category: .ownerDirective,
            actionRequired: true,
            actionDestination: .roster
        ),
        InboxMessage(
            sender: .offensiveCoordinator(name: "Mike McCarthy"),
            subject: "Offensive Personnel Assessment",
            body: "Coach, I've been studying the film from last season...",
            date: "Offseason - Coaching Changes, 2026",
            category: .staffUpdate,
            isRead: true
        ),
        InboxMessage(
            sender: .leagueOffice,
            subject: "Welcome to the Dallas Longriders",
            body: "On behalf of the league office, welcome...",
            date: "Offseason - Coaching Changes, 2026",
            category: .leagueNotice,
            isRead: true
        ),
    ]

    NavigationStack {
        InboxView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            messages: $previewMessages
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
