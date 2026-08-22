import SwiftUI
import SwiftData

// MARK: - LeagueTransactionsView
//
// F-51. The league transaction wire, over the `TradeRecord` ledger.
//
// The ledger has been written at every execution site since Wave 0 — the user's
// deals, the AI-vs-AI market pass, draft-night swaps, forced holdout trades —
// and until F-50 its only reader in the whole binary was a DEBUG smoke test.
// F-50 gave the Trade Center a history card, which is the right card in the
// wrong scope: it is THIS season, THIS club, and it answers "what have I done
// lately". The wire answers the other question a real GM asks, which is what the
// other 31 did and how it compares.
//
// ## What is on a row, and why
//
// The queue's specification is a table of rows with both asset summaries, both
// point totals and the `kind` label. All five are here, and the `kind` label
// earns its place: a deal the user proposed, a deal he accepted off the phone
// and a deal two rivals made are three different things, and until this screen
// existed `TradeRecordKind.label` was dead copy.
//
// The point totals are shown as they were priced, plus a signed delta, and the
// delta is deliberately labelled CHART rather than "grade". The numbers come
// from `TradeValueEngine.proposalValues` at the moment the deal executed; that
// is a real, checkable quantity and it is NOT a verdict. A club that gave up 40
// chart points for the quarterback it needed did not lose the trade. Saying
// "you were 40 light on the chart" is honest; printing a B− is not, and the one
// thing this screen must never become is a scoreboard that pretends to know
// more than the chart does.
//
// From the user's chair, whenever he is in the deal: his own side is always the
// left-hand column, whether the ledger filed him as initiator or partner. The
// wire is read by a GM, not by an archivist.
//
// ## Scope
//
// `@Query` cannot take a runtime predicate built from a stored property, so both
// queries come back store-wide and are narrowed to this save by `careerID` —
// the same pattern `CoachDetailView` uses. Without it a second career's deals
// appear on the first career's wire.

struct LeagueTransactionsView: View {

    let career: Career

    @Query private var allRecordsUnscoped: [TradeRecord]
    @Query private var allTeamsUnscoped: [Team]

    /// Which slice of the wire is showing.
    @State private var lens: Lens = .all
    /// `nil` means every season the save has on file.
    @State private var season: Int?
    @State private var sort = DSSortState<SortKey>(key: .recency)
    @State private var inspected: TradeRecord?

    // MARK: - Lens

    enum Lens: Hashable, CaseIterable {
        case all
        case mine
        case league

        var label: String {
            switch self {
            case .all:    return "Everything"
            case .mine:   return "My club"
            case .league: return "Around the league"
            }
        }

        var icon: String {
            switch self {
            case .all:    return "list.bullet.rectangle"
            case .mine:   return "person.crop.square"
            case .league: return "globe"
            }
        }
    }

    enum SortKey: Hashable {
        case recency
        case chart
        case size
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                wireContent
            }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $inspected) { record in
            transactionDetailSheet(record)
        }
    }

    // MARK: - Filter strip

    private var filterBar: some View {
        VStack(spacing: DSSpacing.xs) {
            DSLensTabs(
                selection: $lens,
                lenses: Lens.allCases,
                label: { $0.label },
                icon: { $0.icon },
                title: "THE WIRE"
            )

            HStack(spacing: DSSpacing.xs) {
                Menu {
                    Button("Every season") { season = nil }
                    ForEach(seasonsOnFile, id: \.self) { year in
                        Button(String(year)) { season = year }
                    }
                } label: {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "calendar")
                        Text(season.map(String.init) ?? "Every season")
                        Image(systemName: "chevron.down")
                    }
                    .font(DSType.display(DSType.Size.caption, .bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, DSSpacing.sm)
                    .frame(minHeight: 44)
                }

                Spacer()

                if !rollupFacts.isEmpty {
                    DSGroupRollup(title: "", facts: rollupFacts)
                }
            }
            .padding(.horizontal, DSSpacing.md)
        }
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.xs)
        .frame(maxWidth: DSLayout.wideMeasure)
        .frame(maxWidth: .infinity)
    }

    // MARK: - The wire

    @ViewBuilder
    private var wireContent: some View {
        if visibleRecords.isEmpty {
            Spacer()
            DSEmptyState(
                icon: "arrow.left.arrow.right",
                title: emptyTitle,
                message: emptyMessage
            )
            .padding(DSSpacing.md)
            .frame(maxWidth: DSLayout.contentMeasure)
            .frame(maxWidth: .infinity)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(visibleRecords) { record in
                            Button { inspected = record } label: { wireRow(record) }
                                .buttonStyle(.plain)
                            Divider().overlay(Color.surfaceBorder)
                        }
                    } header: {
                        wireHeader
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: DSLayout.wideMeasure)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var wireHeader: some View {
        DSListHeaderRow(
            density: .study,
            reservesBadge: true,
            badgeLabel: "WK",
            portraitWidth: 0,
            identityLabel: "DEAL",
            affordance: .disclosure
        ) {
            DSSortableColumnHeader("SENT", key: .chart, sort: $sort, width: DSListColumn.value)
            DSColumnHeader("GOT", width: DSListColumn.value)
            DSSortableColumnHeader("CHART", key: .size, sort: $sort, width: DSListColumn.label)
        }
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.backgroundPrimary)
    }

    private func wireRow(_ record: TradeRecord) -> some View {
        let view = RowView(record: record, userTeamID: career.teamID, teams: teamsByID)
        return DSListRow(
            density: .study,
            badge: DSRowBadge(text: view.weekTag, tint: view.kindTint),
            portraitWidth: 0,
            affordance: .disclosure
        ) {
            EmptyView()
        } identity: {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(view.headline)
                        .font(DSType.display(DSType.Size.body, .heavy))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    DSStatusPill(
                        label: record.kind.label,
                        tone: view.kindTone,
                        showsDot: false
                    )
                }
                Text("Out \u{2192} \(view.outSummary)")
                    .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(2)
                Text("In \u{2190} \(view.inSummary)")
                    .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
        } columns: {
            Text("\(view.outValue)")
                .font(DSType.display(DSType.Size.body, .bold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.value)
            Text("\(view.inValue)")
                .font(DSType.display(DSType.Size.body, .bold))
                .foregroundStyle(Color.textPrimary)
                .dsColumn(DSListColumn.value)
            Text(view.chartDeltaText)
                .font(DSType.display(DSType.Size.body, .heavy))
                .foregroundStyle(view.chartDeltaTint)
                .dsColumn(DSListColumn.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(view.spoken)
        .accessibilityHint("Opens the full transaction")
    }

    // MARK: - Detail sheet
    //
    // The row truncates two asset summaries to keep the table scannable; the
    // sheet is where the untruncated text lives, so nothing on the wire is
    // information the user cannot actually reach.

    private func transactionDetailSheet(_ record: TradeRecord) -> some View {
        let view = RowView(record: record, userTeamID: career.teamID, teams: teamsByID)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(record.kind.label.uppercased()) \u{00B7} \(view.whenLabel)")
                            .font(DSType.display(DSType.Size.caption, .heavy))
                            .tracking(0.7)
                            .foregroundStyle(Color.textSecondary)
                        Text(view.headline)
                            .font(DSType.display(DSType.Size.title2, .heavy))
                            .foregroundStyle(Color.textPrimary)
                    }

                    detailSide(
                        title: view.outTitle,
                        summary: view.outSummary,
                        value: view.outValue,
                        tint: Color.textSecondary
                    )
                    detailSide(
                        title: view.inTitle,
                        summary: view.inSummary,
                        value: view.inValue,
                        tint: Color.accentGold
                    )

                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("ON THE CHART")
                            .font(DSType.display(DSType.Size.caption, .heavy))
                            .tracking(0.7)
                            .foregroundStyle(Color.textSecondary)
                        Text(view.chartVerdict)
                            .font(DSType.text(DSType.Size.body, .semibold, prose: true))
                            .foregroundStyle(view.chartDeltaTint)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.chartCaveat)
                            .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()

                    Text(view.movementLine)
                        .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                        .foregroundStyle(Color.textTertiaryReadable)
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { inspected = nil }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func detailSide(
        title: String, summary: String, value: Int, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack {
                Text(title.uppercased())
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(value) pts")
                    .font(DSType.display(DSType.Size.body, .heavy))
                    .foregroundStyle(tint)
            }
            Text(summary)
                .font(DSType.text(DSType.Size.body, .medium, prose: true))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// The sentence that stops the delta from becoming a verdict.
    static let chartCaveat =
        "Chart points are what the trade calculator priced these assets at on the day. They are a checkable number, not a grade — a club that came out light on the chart for the quarterback it needed did not lose the trade."

    // MARK: - Data

    private var records: [TradeRecord] {
        allRecordsUnscoped.filter { $0.careerID == career.id }
    }

    private var teamsByID: [UUID: Team] {
        Dictionary(
            allTeamsUnscoped.filter { $0.careerID == career.id }.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    private var seasonsOnFile: [Int] {
        Array(Set(records.map(\.season))).sorted(by: >)
    }

    private var visibleRecords: [TradeRecord] {
        let userTeamID = career.teamID
        let filtered = records.filter { record in
            if let season, record.season != season { return false }
            switch lens {
            case .all:    return true
            case .mine:   return !record.isAIvsAI(userTeamID: userTeamID)
            case .league: return record.isAIvsAI(userTeamID: userTeamID)
            }
        }
        // Every sort ends on the record id: SwiftData fetch order is
        // unspecified, so two deals struck in the same week would otherwise
        // swap places between redraws.
        switch sort.key {
        case .recency:
            return filtered.dsSorted(sort.ascending, id: \.id) { lhs, rhs in
                dsCompare(lhs.occurredAt, rhs.occurredAt)
            }
        case .chart:
            return filtered.dsSorted(sort.ascending, by: { $0.sentValue }, id: \.id)
        case .size:
            return filtered.dsSorted(
                sort.ascending,
                by: { abs($0.receivedValue - $0.sentValue) },
                id: \.id
            )
        }
    }

    /// The strip above the table. Deliberately three plain counts and one net —
    /// the wire summarises, it does not editorialise.
    private var rollupFacts: [String] {
        let shown = visibleRecords
        guard !shown.isEmpty else { return [] }
        var facts = ["\(shown.count) deal\(shown.count == 1 ? "" : "s")"]
        let players = shown.reduce(0) { $0 + $1.playersMovedCount }
        let picks = shown.reduce(0) { $0 + $1.picksMovedCount }
        facts.append("\(players) player\(players == 1 ? "" : "s")")
        facts.append("\(picks) pick\(picks == 1 ? "" : "s")")
        if let userTeamID = career.teamID {
            let mine = shown.filter { !$0.isAIvsAI(userTeamID: userTeamID) }
            if !mine.isEmpty {
                let net = mine.reduce(0) { total, record in
                    let view = RowView(record: record, userTeamID: userTeamID, teams: [:])
                    return total + (view.inValue - view.outValue)
                }
                facts.append("your net \(net >= 0 ? "+" : "")\(net) on the chart")
            }
        }
        return facts
    }

    private var emptyTitle: String {
        switch lens {
        case .all:    return season == nil ? "Nothing has moved yet" : "No deals in \(season.map(String.init) ?? "")"
        case .mine:   return "You have not made a trade"
        case .league: return "The league has been quiet"
        }
    }

    private var emptyMessage: String {
        switch lens {
        case .all:
            return "Every completed trade in this league lands here \u{2014} yours, the ones you accept off the phone, the ones two rivals make, and draft-night swaps."
        case .mine:
            return "\(records.count) deal\(records.count == 1 ? "" : "s") on file league-wide, none of them yours. The **Trade Center** is where that changes."
        case .league:
            return "\(records.count) deal\(records.count == 1 ? "" : "s") on file, all of them involving your club. The other 31 trade among themselves as the season runs."
        }
    }

    // MARK: - Row view model
    //
    // One place decides which side of a `TradeRecord` is "ours", so the table,
    // the sheet and the rollup cannot disagree about it (§2.13's arithmetic
    // gate). The ledger stores the deal from the INITIATOR's point of view; the
    // user is the initiator when he built it and the partner when he accepted
    // one off the phone, and the wire always shows him on the left regardless.

    struct RowView {
        let headline: String
        let outTitle: String
        let inTitle: String
        let outSummary: String
        let inSummary: String
        let outValue: Int
        let inValue: Int
        let weekTag: String
        let whenLabel: String
        let kindTone: DSStatusPill.Tone
        let kindTint: Color
        let involvesUser: Bool

        init(record: TradeRecord, userTeamID: UUID?, teams: [UUID: Team]) {
            let initiator = teams[record.initiatorTeamID]?.abbreviation ?? "\u{2014}"
            let partner = teams[record.partnerTeamID]?.abbreviation ?? "\u{2014}"
            let userIsPartner = userTeamID != nil && record.partnerTeamID == userTeamID
            involvesUser = !record.isAIvsAI(userTeamID: userTeamID)

            // Flip the record onto the user's chair when he is the partner. For
            // an AI-vs-AI deal the initiator's chair is used unchanged, which is
            // the only honest choice: neither club is "ours".
            if userIsPartner {
                headline = "\(partner) \u{2194} \(initiator)"
                outTitle = "\(partner) sent"
                inTitle = "\(partner) received"
                outSummary = record.receivedSummary
                inSummary = record.sentSummary
                outValue = record.receivedValue
                inValue = record.sentValue
            } else {
                headline = "\(initiator) \u{2194} \(partner)"
                outTitle = "\(initiator) sent"
                inTitle = "\(initiator) received"
                outSummary = record.sentSummary
                inSummary = record.receivedSummary
                outValue = record.sentValue
                inValue = record.receivedValue
            }

            weekTag = record.isInSeason ? "W\(record.week)" : "OFF"
            whenLabel = record.isInSeason
                ? "\(record.season) \u{00B7} Week \(record.week)"
                : "\(record.season) \u{00B7} \(record.phase.displayName)"

            switch record.kind {
            case .userProposal:  kindTone = .info
            case .aiWeeklyOffer: kindTone = .info
            case .draftDay:      kindTone = .warn
            case .holdoutForced: kindTone = .bad
            default:             kindTone = .neutral
            }
            kindTint = Color.forStatus(kindTone)
        }

        /// Chart points gained or given up, from the chair this row shows.
        var chartDelta: Int { inValue - outValue }

        var chartDeltaText: String {
            chartDelta == 0 ? "even" : (chartDelta > 0 ? "+\(chartDelta)" : "\(chartDelta)")
        }

        /// Colour is only spent where the row has an owner. An AI-vs-AI deal has
        /// no "our" side, so its delta stays neutral rather than telling the
        /// user that Denver's surplus was good news.
        var chartDeltaTint: Color {
            guard involvesUser, chartDelta != 0 else { return .textTertiaryReadable }
            return chartDelta > 0 ? .success : .dangerText
        }

        var chartVerdict: String {
            if chartDelta == 0 { return "Priced dead even: \(outValue) points each way." }
            let side = chartDelta > 0 ? "ahead" : "light"
            return "\(abs(chartDelta)) points \(side) on the chart \u{2014} \(outValue) out, \(inValue) in."
        }

        var movementLine: String {
            "Filed \(whenLabel)."
        }

        var spoken: String {
            "\(headline), \(whenLabel). Sent \(outSummary) for \(inSummary). \(chartVerdict)"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LeagueTransactionsView(
            career: Career(
                playerName: "Mike Johnson",
                avatarID: "avatar_00000",
                role: .gmAndHeadCoach,
                capMode: .simple
            )
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
