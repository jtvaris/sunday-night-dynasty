import SwiftUI
import SwiftData

// MARK: - ShopPlayerSheet
//
// F-58. "Who wants my backup tight end?" — asked from the player's own card.
//
// Wave 3 specified shop-your-own-player and a trade block and shipped neither.
// The rest of the entry-point surface is in reasonable shape (nav bookmark,
// shell route, deadline-week dashboard tile, three `TaskGenerator` tasks, "Trade
// For" on rivals), so this is a gap rather than a rewrite: the one direction
// missing was outward.
//
// The sheet polls all 31 clubs through `ShoppingPoll` and hands off. It does not
// build a package and it does not negotiate — the Trade Center already does both
// properly, and every row here opens it with that club selected and this player
// already ticked in the user's column.
//
// The block toggle lives here too, because the two questions are one motion: you
// find out who is interested and then decide whether to keep the man on your
// list. What the block does and does not do is stated on the row rather than
// implied — see `TradeBlockStore`.

struct ShopPlayerSheet: View {

    let player: Player
    let career: Career
    /// The whole league's players — the poll needs them to build 31 market
    /// views, and the caller already holds them.
    let allPlayers: [Player]

    @Environment(\.dismiss) private var dismiss
    @Query private var allTeamsUnscoped: [Team]
    @ObservedObject private var block = TradeBlockStore.shared

    /// The poll, run once when the sheet opens.
    ///
    /// Building 31 `GMMarketView`s is a real cost — a `needProfile` and a stance
    /// read per club — so it happens on appear and is held, never recomputed in
    /// a body.
    @State private var interests: [ShoppingInterest] = []
    @State private var polled = false
    @State private var openedPartner: Team?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                content
            }
            .safeAreaInset(edge: .bottom) { blockBar }
            .navigationTitle("Shop \(player.lastName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear(perform: runPoll)
            .fullScreenCover(item: $openedPartner) { partner in
                NavigationStack {
                    TradeView(
                        career: career,
                        prefill: TradeView.Prefill(
                            partnerTeamID: partner.id,
                            targetPlayerIDs: [],
                            offeredPlayerIDs: [player.id]
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
    }

    @ViewBuilder
    private var content: some View {
        if !polled {
            ProgressView().tint(Color.accentGold)
        } else if liveInterests.isEmpty {
            DSEmptyState(
                icon: "phone.down",
                title: "Nobody is paying over the chart",
                message: "No club in the league prices \(player.lastName) above his chart value right now. That does not make him untradeable \u{2014} it means any deal for him starts at a discount."
            )
            .padding(DSSpacing.md)
            .frame(maxWidth: DSLayout.contentMeasure)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    ForEach(interests) { interest in
                        Button { open(interest) } label: { interestRow(interest) }
                            .buttonStyle(.plain)
                            .disabled(!interest.talksOpen)
                        Divider().overlay(Color.surfaceBorder)
                    }
                    Text(Self.pollCaveat)
                        .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DSSpacing.sm)
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text("WHO WOULD TAKE THE CALL")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
            Text("\(player.position.rawValue) \(player.fullName), \(player.overall) OVR \u{00B7} chart value \(chartValue) pts")
                .font(DSType.text(DSType.Size.body, .semibold))
                .foregroundStyle(Color.textPrimary)
            Text(ShoppingPoll.summary(interests))
                .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestRow(_ interest: ShoppingInterest) -> some View {
        DSListRow(
            density: .scan,
            badge: DSRowBadge(
                text: interest.abbreviation,
                tint: Color.forStatus(interest.tone)
            ),
            portraitWidth: 0,
            affordance: interest.talksOpen ? .disclosure : .none
        ) {
            EmptyView()
        } identity: {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(interest.fullName)
                        .font(DSType.text(DSType.Size.body, .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    DSStatusPill(label: interest.toneLabel, tone: interest.tone, showsDot: false)
                }
                Text(interest.reason)
                    .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
            }
        } columns: {
            Text("\(interest.value)")
                .font(DSType.display(DSType.Size.body, .bold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.value)
            Text(interest.premiumText)
                .font(DSType.display(DSType.Size.body, .heavy))
                .foregroundStyle(Color.forStatus(interest.tone))
                .dsColumn(DSListColumn.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(interest.fullName). \(interest.toneLabel). \(interest.reason). "
                + "Values him at \(interest.value) points, \(interest.premiumText) over the chart."
        )
        .accessibilityHint(interest.talksOpen
                           ? "Opens the Trade Center with this club"
                           : "This club is not taking your calls")
    }

    // MARK: - The block toggle

    private var blockBar: some View {
        let isListed = block.isListed(player.id)
        let blocked = !isListed && block.isFull
        return DSActionBar(
            explainer: .init(
                title: isListed ? "On the block" : "Your shortlist",
                message: blocked
                    ? "Your block is full at \(TradeBlockStore.maxListed). Take somebody off it first."
                    : Self.blockExplainer,
                isWarning: blocked
            ),
            primary: .init(
                title: isListed ? "Take off the block" : "Put on the block",
                caption: "\(block.count) of \(TradeBlockStore.maxListed) listed",
                isEnabled: !blocked,
                handler: { block.toggle(player.id) }
            )
        )
    }

    /// Says what the block IS, and stops short of what it is not. The engine
    /// does not read it — see `TradeBlockStore` for the exact seam — and no
    /// sentence here suggests otherwise.
    static let blockExplainer =
        "The block is your own shortlist of men you would move. It is a note to yourself, not a press release: **the league does not read it.**"

    static let pollCaveat =
        "These are what each club's GM prices him at, not offers. What they would actually send back depends on their roster and their picks, and that conversation happens in the Trade Center."

    // MARK: - Data

    private var teams: [Team] {
        allTeamsUnscoped.filter { $0.careerID == career.id }
    }

    private var chartValue: Int {
        TradeValueEngine.playerTradeValue(player: player)
    }

    private var liveInterests: [ShoppingInterest] {
        interests.filter { $0.talksOpen && $0.premium >= ShoppingPoll.mildPremium }
    }

    private func runPoll() {
        guard !polled else { return }
        interests = ShoppingPoll.poll(
            player: player,
            userTeamID: career.teamID,
            teams: teams,
            allPlayers: allPlayers,
            season: career.currentSeason,
            week: career.currentWeek
        )
        polled = true
    }

    private func open(_ interest: ShoppingInterest) {
        guard interest.talksOpen else { return }
        openedPartner = teams.first { $0.id == interest.teamID }
    }
}
