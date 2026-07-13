import SwiftUI
import SwiftData

// MARK: - News Filter

private enum NewsFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case trending  = "Trending"
    case myTeam    = "My Team"
    case trades    = "Trades"
    case awards    = "Awards"
    case injuries  = "Injuries"
    case statLines = "Stat Lines"
    case league    = "League"
    case draft     = "Draft"

    var id: String { rawValue }

    /// R38: localized chip label — the raw value stays the stable identifier.
    var label: String {
        switch self {
        case .all:       return String(localized: "All")
        case .trending:  return String(localized: "Trending")
        case .myTeam:    return String(localized: "My Team")
        case .trades:    return String(localized: "Trades")
        case .awards:    return String(localized: "Awards")
        case .injuries:  return String(localized: "Injuries")
        case .statLines: return String(localized: "Stat Lines")
        case .league:    return String(localized: "League")
        case .draft:     return String(localized: "Draft")
        }
    }

    var iconName: String {
        switch self {
        case .all:       return "newspaper"
        case .trending:  return "flame.fill"
        case .myTeam:    return "star.fill"
        case .trades:    return "arrow.left.arrow.right"
        case .awards:    return "trophy.fill"
        case .injuries:  return "cross.case.fill"
        case .statLines: return "chart.bar.fill"
        case .league:    return "sportscourt.fill"
        case .draft:     return "person.crop.square.filled.and.at.rectangle"
        }
    }
}

// MARK: - Date Bucket

private enum DateBucket: String, CaseIterable {
    case today    = "Today"
    case thisWeek = "This Week"
    case earlier  = "Earlier"

    var sortOrder: Int {
        switch self {
        case .today:    return 0
        case .thisWeek: return 1
        case .earlier:  return 2
        }
    }
}

// MARK: - NewsView

struct NewsView: View {

    let career: Career

    @State private var newsItems: [NewsItem] = []
    @State private var activeFilter: NewsFilter = .all
    @State private var expandedItemIDs: Set<UUID> = []

    // MARK: Filtering

    private var sortedItems: [NewsItem] {
        newsItems.sorted {
            if $0.season != $1.season { return $0.season > $1.season }
            return $0.week > $1.week
        }
    }

    private func itemsMatching(_ filter: NewsFilter) -> [NewsItem] {
        switch filter {
        case .all:
            return sortedItems
        case .trending:
            return sortedItems.filter { isTrending($0) }
        case .myTeam:
            guard let teamID = career.teamID else { return [] }
            return sortedItems.filter { $0.relatedTeamID == teamID }
        case .trades:
            return sortedItems.filter { $0.category == .trade }
        case .awards:
            return sortedItems.filter { $0.category == .award }
        case .injuries:
            return sortedItems.filter { $0.category == .injury }
        case .statLines:
            return sortedItems.filter { $0.category == .playerPerformance }
        case .league:
            return sortedItems.filter {
                [.gameResult, .teamRanking, .coachingChange,
                 .offFieldIncident, .retirement, .freeAgency, .contract].contains($0.category)
            }
        case .draft:
            return sortedItems.filter { $0.category == .draft }
        }
    }

    private var filteredItems: [NewsItem] { itemsMatching(activeFilter) }

    /// Pinned stories shown at the top of the feed (1-3 items max).
    private var pinnedTrending: [NewsItem] {
        // Don't double-show pinned items when "Trending" is the active filter.
        guard activeFilter != .trending else { return [] }
        let trending = sortedItems.filter { isTrending($0) }
        return Array(trending.prefix(3))
    }

    private var pinnedIDs: Set<UUID> {
        Set(pinnedTrending.map(\.id))
    }

    private var groupedItems: [(bucket: DateBucket, items: [NewsItem])] {
        // Exclude pinned items so they aren't duplicated below.
        let visible = filteredItems.filter { !pinnedIDs.contains($0.id) }
        let groups = Dictionary(grouping: visible, by: bucket(for:))
        return DateBucket.allCases
            .compactMap { bucket -> (DateBucket, [NewsItem])? in
                guard let items = groups[bucket], !items.isEmpty else { return nil }
                return (bucket, items)
            }
    }

    // MARK: - Body

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
            HStack(spacing: 8) {
                ForEach(NewsFilter.allCases) { filter in
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
        let count = itemsMatching(filter).count
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(filter.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.backgroundPrimary.opacity(0.25)
                                    : Color.backgroundPrimary.opacity(0.5)
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentBlue : Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - News List

    /// R29: storyline state persisted on the career by the narrative engine.
    private var narrative: LeagueNarrativeState? {
        guard let state = career.leagueNarrative,
              state.season == career.currentSeason,
              !state.rankings.isEmpty else { return nil }
        return state
    }

    /// The MVP-race card appears from midseason on (the race needs a body of
    /// work before it means anything).
    private var showMVPRace: Bool {
        guard let narrative else { return false }
        return narrative.week >= 10 && !narrative.mvpRace.isEmpty
    }

    /// League cards render on the default and League feeds only.
    private var showsLeagueCards: Bool {
        narrative != nil && (activeFilter == .all || activeFilter == .league)
    }

    private var newsListContent: some View {
        Group {
            if filteredItems.isEmpty && !showsLeagueCards {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // R29: league cards lead the default + league feeds.
                        if let narrative, showsLeagueCards {
                            PowerRankingsCard(
                                state: narrative,
                                userTeamID: career.teamID
                            )
                            if showMVPRace {
                                MVPRaceCard(
                                    race: narrative.mvpRace,
                                    userTeamID: career.teamID
                                )
                            }
                        }
                        if !pinnedTrending.isEmpty {
                            trendingSection
                        }
                        ForEach(groupedItems, id: \.bucket) { group in
                            dateGroupSection(bucket: group.bucket, items: group.items)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Trending")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            VStack(spacing: 12) {
                ForEach(pinnedTrending) { item in
                    NewsItemCard(
                        item: item,
                        isMyTeam: item.relatedTeamID == career.teamID,
                        isExpanded: expandedItemIDs.contains(item.id),
                        isPinned: true
                    ) {
                        toggleExpansion(item.id)
                    }
                }
            }
        }
    }

    // MARK: Date Group Section

    private func dateGroupSection(bucket: DateBucket, items: [NewsItem]) -> some View {
        // R29: within each date bucket the feed reads "Your Team" first,
        // then "League News" (sub-labels only shown when both exist).
        let myTeamItems = items.filter { career.teamID != nil && $0.relatedTeamID == career.teamID }
        let leagueItems = items.filter { !(career.teamID != nil && $0.relatedTeamID == career.teamID) }
        let showSubLabels = !myTeamItems.isEmpty && !leagueItems.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(bucket.rawValue)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            if showSubLabels {
                newsSubLabel(String(localized: "Your Team"), icon: "star.fill", color: Color.accentGold)
            }
            VStack(spacing: 12) {
                ForEach(myTeamItems) { item in
                    NewsItemCard(
                        item: item,
                        isMyTeam: true,
                        isExpanded: expandedItemIDs.contains(item.id),
                        isPinned: false
                    ) {
                        toggleExpansion(item.id)
                    }
                }
            }
            if showSubLabels {
                newsSubLabel(String(localized: "League News"), icon: "sportscourt.fill", color: Color.textTertiary)
            }
            VStack(spacing: 12) {
                ForEach(leagueItems) { item in
                    NewsItemCard(
                        item: item,
                        isMyTeam: false,
                        isExpanded: expandedItemIDs.contains(item.id),
                        isPinned: false
                    ) {
                        toggleExpansion(item.id)
                    }
                }
            }
        }
    }

    private func newsSubLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundStyle(color)
        .padding(.top, 2)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: activeFilter == .all ? "newspaper" : activeFilter.iconName)
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var emptyStateTitle: String {
        switch activeFilter {
        case .all:    return "No news yet"
        default:      return "No \(activeFilter.rawValue.lowercased()) stories"
        }
    }

    private var emptyStateMessage: String {
        switch activeFilter {
        case .all:
            return "Stories will appear here as the season progresses."
        case .myTeam:
            return "Stories involving your team will be highlighted here."
        case .trending:
            return "Big stories — championships, blockbuster trades, major awards — show up here."
        default:
            return "Try a different filter or come back later in the season."
        }
    }

    // MARK: - Helpers

    private func toggleExpansion(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedItemIDs.contains(id) {
                expandedItemIDs.remove(id)
            } else {
                expandedItemIDs.insert(id)
            }
        }
    }

    /// A story is "trending" / high impact if it's a championship-level award,
    /// a blockbuster trade, a major coaching change, or a notable retirement.
    private func isTrending(_ item: NewsItem) -> Bool {
        switch item.category {
        case .award where item.sentiment == .positive:
            return true
        case .trade:
            return true
        case .retirement:
            return true
        case .coachingChange where item.sentiment != .neutral:
            return true
        case .teamRanking where item.sentiment == .positive:
            // championship / playoff clinches are typically positive ranking stories
            let lowered = item.headline.lowercased()
            return lowered.contains("champion")
                || lowered.contains("super bowl")
                || lowered.contains("playoff")
                || lowered.contains("clinch")
        default:
            return false
        }
    }

    private func bucket(for item: NewsItem) -> DateBucket {
        // "Today" = same season + same week as the career clock.
        // "This Week" = within 1 week of the career clock (same season).
        // "Earlier" = anything older.
        if item.season == career.currentSeason && item.week == career.currentWeek {
            return .today
        }
        if item.season == career.currentSeason &&
           career.currentWeek - item.week <= 1 &&
           career.currentWeek - item.week >= 0 {
            return .thisWeek
        }
        return .earlier
    }

    // MARK: - Data

    private func loadNews() {
        // R29: the news feed is persisted on the career (JSON-encoded,
        // newest first) by WeekAdvancer after every advance.
        newsItems = career.newsLog
    }
}

// MARK: - NewsItemCard

private struct NewsItemCard: View {

    let item: NewsItem
    let isMyTeam: Bool
    let isExpanded: Bool
    let isPinned: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left accent strip — gold for "my team", flame-gold for pinned.
                if isPinned || isMyTeam {
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
                    // Header row: pinned flag + category badge + sentiment + week
                    HStack(spacing: 8) {
                        if isPinned {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("TRENDING")
                                    .font(.system(size: 10, weight: .heavy))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(Color.accentGold)
                        }
                        categoryBadge(item.category)
                        if isMyTeam {
                            Text("MY TEAM")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.5)
                                .foregroundStyle(Color.accentGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().stroke(Color.accentGold.opacity(0.5), lineWidth: 1)
                                )
                        }
                        Spacer()
                        sentimentDot(item.sentiment)
                        Text("Wk \(item.week)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .monospacedDigit()
                    }

                    // Headline
                    Text(item.headline)
                        .font(isPinned
                              ? .headline.weight(.bold)
                              : .subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)

                    // Body — full text when expanded, 3 lines preview otherwise.
                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Read more / Show less affordance
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Read more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentBlue)
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var cardFill: Color {
        // Pinned cards get a slightly elevated tint for emphasis.
        isPinned ? Color.backgroundTertiary : Color.backgroundSecondary
    }

    private var borderColor: Color {
        if isPinned { return Color.accentGold.opacity(0.55) }
        if isMyTeam { return Color.accentGold.opacity(0.4) }
        return Color.surfaceBorder
    }

    private var borderWidth: CGFloat {
        isPinned ? 1.25 : 1
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

// MARK: - Power Rankings Card (R29)

private struct PowerRankingsCard: View {

    let state: LeagueNarrativeState
    let userTeamID: UUID?

    /// Top-10 always; the user's team is appended when it sits below the line.
    private var visibleEntries: [PowerRankingEntry] {
        let topTen = Array(state.rankings.prefix(10))
        guard let userTeamID,
              let userEntry = state.rankings.first(where: { $0.teamID == userTeamID }),
              userEntry.rank > 10 else {
            return topTen
        }
        return topTen + [userEntry]
    }

    private var userBelowLine: Bool {
        guard let userTeamID,
              let userEntry = state.rankings.first(where: { $0.teamID == userTeamID }) else {
            return false
        }
        return userEntry.rank > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentBlue)
                Text("Power Rankings")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("Week \(state.week)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }

            VStack(spacing: 6) {
                ForEach(visibleEntries) { entry in
                    if userBelowLine && entry.teamID == userTeamID {
                        HStack {
                            Image(systemName: "ellipsis")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                        }
                        .padding(.leading, 12)
                    }
                    rankingRow(entry)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func rankingRow(_ entry: PowerRankingEntry) -> some View {
        let isUserTeam = entry.teamID == userTeamID
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(entry.rank <= 3 ? Color.accentGold : Color.textSecondary)
                .frame(width: 26, alignment: .trailing)

            movementBadge(entry.movement)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.teamAbbr)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isUserTeam ? Color.accentGold : Color.textPrimary)
                    Text(entry.teamName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(entry.record)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }
                Text(entry.blurb)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isUserTeam ? Color.accentGold.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isUserTeam ? Color.accentGold.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    @ViewBuilder
    private func movementBadge(_ movement: Int) -> some View {
        if movement > 0 {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(movement)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.success)
            .accessibilityLabel("Up \(movement) spots")
        } else if movement < 0 {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(-movement)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.danger)
            .accessibilityLabel("Down \(-movement) spots")
        } else {
            Text("—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityLabel("No movement")
        }
    }
}

// MARK: - MVP Race Card (R29)

private struct MVPRaceCard: View {

    let race: [MVPCandidate]
    let userTeamID: UUID?

    private var leaderPoints: Double {
        max(race.map(\.points).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.accentGold)
                Text("MVP Race")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(Array(race.enumerated()), id: \.element.id) { index, candidate in
                    candidateRow(candidate, position: index + 1)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func candidateRow(_ candidate: MVPCandidate, position: Int) -> some View {
        let isUserTeam = candidate.teamID != nil && candidate.teamID == userTeamID
        let share = candidate.points / leaderPoints
        return HStack(spacing: 10) {
            Text("\(position)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(position == 1 ? Color.accentGold : Color.textSecondary)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isUserTeam ? Color.accentGold : Color.textPrimary)
                        .lineLimit(1)
                    Text("\(candidate.positionRaw) · \(candidate.teamAbbr)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                // Relative "case strength" bar vs. the race leader.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.backgroundTertiary)
                        Capsule()
                            .fill(position == 1 ? Color.accentGold : Color.accentBlue)
                            .frame(width: max(8, geo.size.width * share))
                    }
                }
                .frame(height: 5)
            }
        }
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
        case .trade:             return Color(red: 0.55, green: 0.45, blue: 0.85)
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
