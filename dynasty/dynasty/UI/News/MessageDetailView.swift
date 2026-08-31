import SwiftUI

// MARK: - MessageDetailView

/// Full message detail view showing the complete message body, sender info,
/// and actionable attachment buttons that navigate to relevant views.
struct MessageDetailView: View {

    let message: InboxMessage
    var onNavigate: ((TaskDestination) -> Void)?
    /// Called once when the detail view appears so the caller can mark
    /// the message as read in the source list.
    var onAppear: (() -> Void)?
    /// Called when an Action Required letter has been dealt with — either the
    /// user followed its call to action or marked it handled by hand. Reading a
    /// letter is not doing what it asked, so `onAppear` cannot serve here.
    var onMarkHandled: (() -> Void)?

    // MARK: - Replies
    //
    // The tray was one-way. These three carry the answer side; the caller
    // decides what is offerable, because only the caller can see the roster,
    // the owner row and the rest of the mailbox.

    /// Replies this letter can take right now. Empty means no reply control —
    /// which is the correct rendering for a sender with no system behind it,
    /// for a letter whose decision is made on another screen, and for a letter
    /// already answered. See `InboxEngine.replyOptions(for:)`.
    var replyOptions: [InboxEngine.ReplyOption] = []
    /// Set when this letter *could* be answered but the season's budget on its
    /// channel is spent. Shown in place of the buttons, so the absence of a
    /// control is explained rather than silent.
    var replyBudgetNote: String?
    /// Books the reply and hands back the receipt — the movement that actually
    /// landed. `nil` means nothing was booked and nothing is claimed.
    var onReply: ((InboxEngine.ReplyOption) -> String?)?

    @Environment(\.dismiss) private var dismiss

    /// Local mirror of `message.actionCompleted`. The sheet is handed a value
    /// copy, so the badge has to reflect the resolution itself rather than wait
    /// for the list to hand back a fresh message.
    @State private var isHandled = false

    /// Local mirror of the sent reply, for the same reason `isHandled` is one:
    /// the sheet holds a value copy of the message, so the thread it prints
    /// after the coach hits send has to come from here.
    @State private var sentReplyLabel: String?
    @State private var sentReplyReceipt: String?

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
                            if isHandled {
                                handledBadge
                            } else {
                                actionRequiredBadge
                            }
                        }
                        Spacer()
                        Text(message.date)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Body
                    bodyBlocks

                    // Attachments
                    if !message.attachments.isEmpty {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        attachmentsSection
                    }

                    // The answer side. Present only where a system is actually
                    // waiting for it — see `InboxEngine.replyOptions(for:)`.
                    if sentReplyLabel != nil || !replyOptions.isEmpty || replyBudgetNote != nil {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        replySection
                    }

                    // CTA to open the related screen. Shown for any message
                    // that has a destination — Action Required messages get
                    // a high-emphasis gold button, regular messages get a
                    // softer outlined "Open [destination] →" link.
                    if let destination = message.actionDestination {
                        actionButton(destination: destination, emphasized: message.actionRequired)
                    }

                    // The only other way an Action Required letter can clear:
                    // the user says so. Without this a letter whose work was
                    // done elsewhere sat red in the tray forever.
                    if message.actionRequired && !isHandled {
                        markHandledButton
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
        .onAppear {
            isHandled = message.actionCompleted
            sentReplyLabel = message.sentReplyLabel
            sentReplyReceipt = message.sentReplyReceipt
            onAppear?()
        }
    }

    // MARK: - Reply

    /// Three states, one section: the reply already sent, the replies still
    /// available, or the reason there are none. The third is the important one
    /// — an empty space where a control used to be teaches the user nothing.
    @ViewBuilder
    private var replySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                Text(sentReplyLabel == nil ? "YOUR REPLY" : "YOU REPLIED")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
            }

            if let label = sentReplyLabel {
                sentReplyBlock(label: label, receipt: sentReplyReceipt)
            } else if !replyOptions.isEmpty {
                ForEach(replyOptions) { option in
                    replyButton(option)
                }
            } else if let note = replyBudgetNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sentReplyBlock(label: String, receipt: String?) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("\u{201C}\(label)\u{201D}")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let receipt {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.success)
                    Text(receipt)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.success.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// The button carries its own consequence: `option.forecast` is the exact
    /// movement `InboxEngine.applyReply` will book, so nothing about the
    /// exchange is a surprise after the fact.
    private func replyButton(_ option: InboxEngine.ReplyOption) -> some View {
        Button {
            send(option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.forecast)
                        .font(.caption)
                        .foregroundStyle(option.delta >= 0 ? Color.success : Color.danger)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .padding(DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label). \(option.forecast)")
    }

    private func send(_ option: InboxEngine.ReplyOption) {
        guard sentReplyLabel == nil else { return }
        // Only claim what the caller says actually landed. A refused booking
        // leaves the buttons alone rather than printing a reply that moved
        // nothing.
        guard let receipt = onReply?(option) else { return }
        sentReplyLabel = option.label
        sentReplyReceipt = receipt
    }

    // MARK: - Body

    /// One block of the message body: a run of prose, or a run of the "- "
    /// lines the generators write.
    private enum BodyBlock {
        case paragraph(String)
        case bullets([String])
    }

    /// The generators have always written their lists as literal `- ` lines
    /// ("- Several prospects at positions of need tested exceptionally well").
    /// Rendered as one raw string those stayed hyphens in a wall of prose, so
    /// the one part of a letter meant to be scanned was the hardest to scan.
    private var parsedBody: [BodyBlock] {
        var blocks: [BodyBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n")
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            blocks.append(.paragraph(text))
        }

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bullets(bullets))
            bullets.removeAll()
        }

        for rawLine in message.body.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("\u{2022} ") {
                flushParagraph()
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty {
                flushParagraph()
                flushBullets()
            } else {
                flushBullets()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    private var bodyBlocks: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(parsedBody.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\u{2022}")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(Color.accentGold)
                                Text(item)
                                    .font(.body)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sender Header

    private var senderHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: message.sender.icon)
                .font(.system(size: DSType.Size.title2))
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

    private var handledBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
            Text("Handled")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.success)
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

    private func actionButton(destination: TaskDestination, emphasized: Bool) -> some View {
        Button {
            // Following the letter's own call to action IS the completion
            // criterion for an Action Required letter — the user has been sent
            // to the screen the letter asked about.
            resolveActionIfNeeded()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onNavigate?(destination)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                Text("Open \(destination.inboxDisplayName)")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(emphasized ? Color.backgroundPrimary : Color.accentGold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(emphasized ? Color.accentGold : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                emphasized ? Color.clear : Color.accentGold.opacity(0.6),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var markHandledButton: some View {
        Button {
            resolveActionIfNeeded()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14))
                Text("Mark as handled")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func resolveActionIfNeeded() {
        guard message.actionRequired, !isHandled else { return }
        isHandled = true
        onMarkHandled?()
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
        case .developmentStaff:         return Color.eliteGreen
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
