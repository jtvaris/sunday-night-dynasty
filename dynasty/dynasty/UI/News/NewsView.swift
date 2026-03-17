import SwiftUI
import SwiftData

// MARK: - News Filter

private enum NewsFilter: String, CaseIterable {
    case all      = "All"
    case myTeam   = "My Team"
    case league   = "League"
    case draft    = "Draft"
}

// MARK: - NewsView

struct NewsView: View {

    let career: Career

    @State private var newsItems: [NewsItem] = []
    @State private var activeFilter: NewsFilter = .all
    @State private var expandedItemIDs: Set<UUID> = []

    private var filteredItems: [NewsItem] {
        let sorted = newsItems.sorted { $0.week > $1.week }
        switch activeFilter {
        case .all:
            return sorted
        case .myTeam:
            guard let teamID = career.teamID else { return [] }
            return sorted.filter { $0.relatedTeamID == teamID }
        case .league:
            return sorted.filter {
                [.gameResult, .teamRanking, .coachingChange, .offFieldIncident, .retirement, .award].contains($0.category)
            }
        case .draft:
            return sorted.filter { $0.category == .draft }
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                newsListContent
            }
        }
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadNews() }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(NewsFilter.allCases, id: \.self) { filter in
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

    private func filterChip(_ filter: NewsFilter) -> some View {
        let isSelected = activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - News List

    private var newsListContent: some View {
        Group {
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            NewsItemCard(
                                item: item,
                                isMyTeam: item.relatedTeamID == career.teamID,
                                isExpanded: expandedItemIDs.contains(item.id)
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedItemIDs.contains(item.id) {
                                        expandedItemIDs.remove(item.id)
                                    } else {
                                        expandedItemIDs.insert(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No news yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Stories will appear here as the season progresses.")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Data

    private func loadNews() {
        // NewsItem is a plain Codable struct, not a SwiftData model.
        // In a full implementation this would load from the career's stored news.
        // For now, initialize with an empty array until news is generated.
        newsItems = []
    }
}

// MARK: - NewsItemCard

private struct NewsItemCard: View {

    let item: NewsItem
    let isMyTeam: Bool
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Gold left border for player's team items
                if isMyTeam {
                    Rectangle()
                        .fill(Color.accentGold)
                        .frame(width: 4)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Header row: category badge + sentiment + week
                    HStack(spacing: 8) {
                        categoryBadge(item.category)
                        Spacer()
                        sentimentDot(item.sentiment)
                        Text("Wk \(item.week)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .monospacedDigit()
                    }

                    // Headline
                    Text(item.headline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)

                    // Body
                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .multilineTextAlignment(.leading)

                    if !isExpanded {
                        Text("Read more")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isMyTeam ? Color.accentGold.opacity(0.4) : Color.surfaceBorder,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryBadge(_ category: NewsCategory) -> some View {
        Text(category.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(category.badgeColor)
            )
    }

    private func sentimentDot(_ sentiment: NewsSentiment) -> some View {
        Circle()
            .fill(sentiment.color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(sentiment.accessibilityLabel)
    }
}

// MARK: - NewsCategory Display Helpers

extension NewsCategory {
    var displayName: String {
        switch self {
        case .gameResult:        return "Game"
        case .injury:            return "Injury"
        case .trade:             return "Trade"
        case .freeAgency:        return "FA"
        case .draft:             return "Draft"
        case .coachingChange:    return "Coaching"
        case .playerPerformance: return "Performance"
        case .teamRanking:       return "Rankings"
        case .offFieldIncident:  return "Off-Field"
        case .contract:          return "Contract"
        case .retirement:        return "Retirement"
        case .award:             return "Award"
        }
    }

    var badgeColor: Color {
        switch self {
        case .gameResult:        return Color.accentBlue
        case .injury:            return Color.danger
        case .trade:             return Color.accentGold
        case .freeAgency:        return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .draft:             return Color.success
        case .coachingChange:    return Color(red: 0.9, green: 0.45, blue: 0.1)
        case .playerPerformance: return Color.accentBlue.opacity(0.8)
        case .teamRanking:       return Color(red: 0.2, green: 0.6, blue: 0.6)
        case .offFieldIncident:  return Color.danger.opacity(0.7)
        case .contract:          return Color.warning
        case .retirement:        return Color.textTertiary
        case .award:             return Color.accentGold
        }
    }
}

// MARK: - NewsSentiment Display Helpers

extension NewsSentiment {
    var color: Color {
        switch self {
        case .positive: return Color.success
        case .negative: return Color.danger
        case .neutral:  return Color.textTertiary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .positive: return "Positive news"
        case .negative: return "Negative news"
        case .neutral:  return "Neutral news"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NewsView(career: Career(
            playerName: "Alex Reid",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self], inMemory: true)
}
