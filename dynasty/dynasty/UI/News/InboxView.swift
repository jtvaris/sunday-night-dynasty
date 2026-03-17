import SwiftUI
import SwiftData

// MARK: - InboxView

/// Football Manager-inspired inbox showing messages from the owner, coordinators,
/// scouts, media, and league office. Provides an immersive management experience.
struct InboxView: View {

    let career: Career
    @Binding var messages: [InboxMessage]
    var onNavigate: ((TaskDestination) -> Void)?

    @State private var activeFilter: InboxFilter = .all
    @State private var selectedMessage: InboxMessage?

    private var filteredMessages: [InboxMessage] {
        messages
            .filter { activeFilter.matches($0) }
            .reversed() // newest first (messages are appended chronologically)
    }

    private var unreadCount: Int {
        messages.filter { !$0.isRead }.count
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .sheet(item: $selectedMessage) { message in
            NavigationStack {
                MessageDetailView(
                    message: message,
                    onNavigate: { destination in
                        selectedMessage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onNavigate?(destination)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.surfaceBorder)
        }
    }

    private func filterChip(_ filter: InboxFilter) -> some View {
        let isSelected = activeFilter == filter
        let filterUnread = messages.filter { !$0.isRead && filter.matches($0) }.count

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Text(filter.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)

                if filterUnread > 0 && !isSelected {
                    Text("\(filterUnread)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentGold))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageListContent: some View {
        Group {
            if filteredMessages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMessages) { message in
                            messageRow(message)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func messageRow(_ message: InboxMessage) -> some View {
        Button {
            // Mark as read
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isRead = true
                selectedMessage = messages[index]
            }
        } label: {
            HStack(spacing: 12) {
                // Unread indicator
                Circle()
                    .fill(message.isRead ? Color.clear : Color.accentGold)
                    .frame(width: 8, height: 8)

                // Sender icon
                Image(systemName: message.sender.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor(for: message.sender))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(iconColor(for: message.sender).opacity(0.15))
                    )

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.sender.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)

                        if message.actionRequired {
                            Text("ACTION")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.danger))
                        }

                        Spacer()

                        Text(message.date)
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }

                    Text(message.subject)
                        .font(.subheadline.weight(message.isRead ? .regular : .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(message.body)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(message.isRead ? Color.backgroundSecondary : Color.backgroundSecondary.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                message.actionRequired ? Color.accentGold.opacity(0.4) : Color.surfaceBorder,
                                lineWidth: message.actionRequired ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No messages")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Messages from your staff, owner, scouts, and media will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
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
            subject: "Welcome to the Dallas Cowboys",
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
