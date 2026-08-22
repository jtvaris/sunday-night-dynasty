import SwiftUI
import SwiftData

// MARK: - TradeBlockView
//
// F-58, the half that persists. The men the user has said he would move, with
// the league's current appetite for each.
//
// The Trade Center's builder is partner-first: it is a good way to answer "what
// can I get from Denver" and a poor way to answer "who wants my backup tight
// end". The block is the standing version of the second question — a shortlist
// the user keeps, re-polled every time he opens it, because a club's appetite
// moves with its record, its needs and the calendar.
//
// The screen is deliberately honest about its own reach. The block is a note to
// the user, the engine does not read it, and the explainer says so. The seam
// that would change that is named on `TradeBlockStore` and is one line in
// `shoppingTarget`; it is another agent's file this wave.

struct TradeBlockView: View {

    let career: Career

    @Query private var allPlayersUnscoped: [Player]
    @Query private var allTeamsUnscoped: [Team]
    @ObservedObject private var block = TradeBlockStore.shared

    /// Poll results per listed player, refreshed when the screen opens.
    ///
    /// One poll builds 31 market views, so a block of eight is 248 of them. It
    /// runs once on appear and after any listing change, never in a body.
    @State private var polls: [UUID: [ShoppingInterest]] = [:]
    @State private var shopping: Player?
    @State private var openedPartner: Team?
    @State private var openedFor: Player?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .bottom) { explainerBar }
        .navigationTitle("Trade Block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: refresh)
        // One `.sheet` on this hierarchy, `item:`-driven, per the house rule.
        .sheet(item: $shopping, onDismiss: refresh) { player in
            ShopPlayerSheet(player: player, career: career, allPlayers: leaguePlayers)
        }
        .fullScreenCover(item: $openedPartner) { partner in
            NavigationStack {
                TradeView(
                    career: career,
                    prefill: TradeView.Prefill(
                        partnerTeamID: partner.id,
                        targetPlayerIDs: [],
                        offeredPlayerIDs: openedFor.map { [$0.id] } ?? []
                    )
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { openedPartner = nil }
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if listedPlayers.isEmpty {
            DSEmptyState(
                icon: "tray",
                title: "Nobody on the block",
                message: "Open any of your players and tap **Shop him** to see which clubs would take the call. Anyone you list turns up here with the league's current appetite for him."
            )
            .padding(DSSpacing.md)
            .frame(maxWidth: DSLayout.contentMeasure)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listedPlayers) { player in
                        blockRow(player)
                        Divider().overlay(Color.surfaceBorder)
                    }
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: DSLayout.wideMeasure)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func blockRow(_ player: Player) -> some View {
        let interests = polls[player.id] ?? []
        let best = interests.first { $0.talksOpen && $0.premium >= ShoppingPoll.mildPremium }
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button { shopping = player } label: {
                DSListRow(
                    density: .scan,
                    badge: DSRowBadge(text: player.position.rawValue, tint: Color.accentBlue),
                    portraitWidth: 0,
                    affordance: .disclosure
                ) {
                    EmptyView()
                } identity: {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(player.fullName)
                            .font(DSType.text(DSType.Size.body, .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(ShoppingPoll.summary(interests))
                            .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(2)
                    }
                } columns: {
                    Text("\(player.overall)")
                        .font(DSType.display(DSType.Size.body, .heavy))
                        .foregroundStyle(Color.forRating(player.overall))
                        .dsColumn(DSListColumn.ovr)
                    Text("\(TradeValueEngine.playerTradeValue(player: player))")
                        .font(DSType.display(DSType.Size.body, .bold))
                        .foregroundStyle(Color.textSecondary)
                        .dsColumn(DSListColumn.value)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the shopping poll for this player")

            HStack(spacing: DSSpacing.xs) {
                if let best {
                    Button {
                        openedFor = player
                        openedPartner = teams.first { $0.id == best.teamID }
                    } label: {
                        Text("Call \(best.abbreviation)")
                    }
                    .buttonStyle(.dsSecondary)
                }
                Button("Take off the block") { block.unlist(player.id); refresh() }
                    .buttonStyle(.dsGhost)
                Spacer()
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private var explainerBar: some View {
        DSActionBar(
            explainer: .init(
                title: "What the block is",
                message: ShopPlayerSheet.blockExplainer
            )
        )
    }

    // MARK: - Data

    private var leaguePlayers: [Player] {
        allPlayersUnscoped.filter { $0.careerID == career.id && !$0.isRetired }
    }

    private var teams: [Team] {
        allTeamsUnscoped.filter { $0.careerID == career.id }
    }

    private var roster: [Player] {
        leaguePlayers.filter { $0.teamID == career.teamID }
    }

    /// Listed players, in the order the user listed them.
    private var listedPlayers: [Player] {
        let byID = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return block.listedIDs.compactMap { byID[$0] }
    }

    /// Drops anyone who left the roster, then re-polls the survivors.
    private func refresh() {
        block.prune(toRosterIDs: Set(roster.map(\.id)))
        let league = leaguePlayers
        let clubs = teams
        var next: [UUID: [ShoppingInterest]] = [:]
        for player in listedPlayers {
            next[player.id] = ShoppingPoll.poll(
                player: player,
                userTeamID: career.teamID,
                teams: clubs,
                allPlayers: league,
                season: career.currentSeason,
                week: career.currentWeek
            )
        }
        polls = next
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradeBlockView(
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
