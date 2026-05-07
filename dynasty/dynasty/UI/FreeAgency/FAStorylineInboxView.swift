import SwiftUI

/// Scrollable inbox of historical FA storyline events (newest first). Shares
/// icon + tint mapping with FAStorylineToast via FAStorylineIcons.
struct FAStorylineInboxView: View {
    let events: [FAStorylineEvent]

    var body: some View {
        ScrollView {
            if sortedEvents.isEmpty {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.textTertiary)
                    Text("No storylines yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Major free-agency moments will appear here.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(DSSpacing.xl)
            } else {
                LazyVStack(spacing: DSSpacing.xs) {
                    ForEach(sortedEvents, id: \.id) { event in
                        eventRow(event)
                    }
                }
                .padding(DSSpacing.md)
            }
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("FA Storylines")
    }

    private var sortedEvents: [FAStorylineEvent] {
        events.sorted { $0.occurredAt > $1.occurredAt }
    }

    private func eventRow(_ event: FAStorylineEvent) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            VStack {
                Image(systemName: FAStorylineIcons.icon(for: event.type))
                    .foregroundStyle(FAStorylineIcons.tint(for: event.type))
                    .font(.title3)
                Spacer(minLength: 0)
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(event.body)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.occurredAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }
}
