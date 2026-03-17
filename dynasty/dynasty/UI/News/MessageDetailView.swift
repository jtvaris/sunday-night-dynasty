import SwiftUI

// MARK: - MessageDetailView

/// Full message detail view showing the complete message body, sender info,
/// and actionable attachment buttons that navigate to relevant views.
struct MessageDetailView: View {

    let message: InboxMessage
    var onNavigate: ((TaskDestination) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Sender header
                    senderHeader

                    Divider().overlay(Color.surfaceBorder)

                    // Subject
                    Text(message.subject)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    // Category and date
                    HStack(spacing: 10) {
                        categoryBadge
                        if message.actionRequired {
                            actionRequiredBadge
                        }
                        Spacer()
                        Text(message.date)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Body
                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Attachments
                    if !message.attachments.isEmpty {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        attachmentsSection
                    }

                    // Action button for actionRequired messages
                    if let destination = message.actionDestination {
                        actionButton(destination: destination)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(Color.accentGold)
            }
        }
    }

    // MARK: - Sender Header

    private var senderHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: message.sender.icon)
                .font(.system(size: 24))
                .foregroundStyle(senderColor)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(senderColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(message.sender.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(message.sender.roleLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Badges

    private var categoryBadge: some View {
        Text(message.category.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(categoryColor)
            )
    }

    private var actionRequiredBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("Action Required")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.danger)
        )
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                Text("ATTACHMENTS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
            }

            ForEach(message.attachments) { attachment in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onNavigate?(attachment.destination)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentBlue)

                        Text(attachment.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.backgroundTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.accentBlue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Button

    private func actionButton(destination: TaskDestination) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onNavigate?(destination)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                Text("Take Action")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentGold)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Colors

    private var senderColor: Color {
        switch message.sender {
        case .owner:                    return Color.accentGold
        case .offensiveCoordinator:     return Color.accentBlue
        case .defensiveCoordinator:     return Color.danger
        case .scout:                    return Color.success
        case .media:                    return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .leagueOffice:             return Color.warning
        case .playerAgent:              return Color.textSecondary
        }
    }

    private var categoryColor: Color {
        switch message.category {
        case .rosterAnalysis:   return Color.accentBlue
        case .staffUpdate:      return Color(red: 0.9, green: 0.45, blue: 0.1)
        case .scoutingReport:   return Color.success
        case .tradeOffer:       return Color.accentGold
        case .contractRequest:  return Color.warning
        case .mediaRequest:     return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .ownerDirective:   return Color.accentGold
        case .leagueNotice:     return Color.textTertiary
        case .playerIssue:      return Color.danger
        case .gamePrep:         return Color.accentBlue
        case .draftPrep:        return Color.success
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessageDetailView(
            message: InboxMessage(
                sender: .owner(name: "Jerry Jones"),
                subject: "Welcome -- Roster Assessment Needed",
                body: """
                Coach,

                I'd like your assessment of our current roster. Who are our key players? Where do we need to improve? Please review the team and let me know your thoughts.

                This is your franchise now. I trust your judgment, but I want to make sure we're aligned on the direction before the offseason really gets going.

                Take a look at the roster evaluation report and let's discuss.

                Jerry Jones
                """,
                date: "Offseason - Coaching Changes, 2026",
                category: .ownerDirective,
                actionRequired: true,
                actionDestination: .roster,
                attachments: [
                    MessageAttachment(title: "View Roster Evaluation", destination: .roster)
                ]
            )
        )
    }
}
