import SwiftUI

/// "Call about moving up" — the draft room's phone.
///
/// Wave 4 (plan §6 Wave 4 / finding S6: "no user trade-UP path exists at all",
/// the most-wanted GM move). Every callable slot ahead of the user is priced by
/// the club that owns it — his persona's hidden chart lean, his stance and his
/// needs — and answered with the best package the user can actually assemble.
/// Unaffordable quotes stay on the list with the gap spelled out, because "here
/// is the price and here is what you're missing" is the useful answer.
///
/// ## #197 — one commit, one gold, one voice
///
/// The sheet shipped with a `MAKE THE CALL` `borderedProminent` gold button on
/// EVERY affordable quote: eight primaries down one scroll, i.e. eight of the
/// one gold fill a screen is allowed (P5 / P7). It also carried fourteen raw
/// font literals and not a single `DSType` token, which is why its type sat a
/// step off every other draft surface.
///
/// What replaced it is the pattern the rest of the app already uses: a quote is
/// SELECTED (a `DSListRow`, one radio column, no button), and the screen's one
/// gold fill lives on the `DSActionBar` at the bottom, where the explainer can
/// finally state the price and the gap in the same sentence as the commit.
///
/// The slot that is on the clock right now leads the list under an `ON THE
/// CLOCK` pill. It is the most valuable and most perishable line on the board —
/// the only one where a call buys the pick being announced — and the engine's
/// ascending pick order buried it whenever a target prospect narrowed the list.
struct TradeUpBoardSheet: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    /// The chosen quote, keyed by the TARGET PICK NUMBER rather than by
    /// `DraftTradeOffer.id`: `id` is a fresh `UUID()` per construction, so every
    /// re-price (the veterans toggle, an executed trade) would silently drop the
    /// selection and leave the action bar dead.
    @State private var selectedPickNumber: Int?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                header

                if let message = coordinator.tradeUpMessage {
                    Text(message)
                        .font(DSType.text(DSType.Size.body, .medium))
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DSSpacing.sm)
                }

                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(orderedQuotes) { quote in
                            quoteRow(quote)
                        }
                    }
                    .padding(.bottom, DSSpacing.md)
                }
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.backgroundPrimary)
            .safeAreaInset(edge: .bottom) {
                callActionBar
            }
            .navigationTitle("Trade Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { coordinator.closeTradeUpBoard() }
                }
            }
        }
    }

    // MARK: - Ordering

    /// The pick currently being announced, when the phone can still buy it.
    private var onTheClockPickNumber: Int? {
        coordinator.currentPick?.pickNumber
    }

    private func targetPickNumber(_ quote: DraftDayTradeEngine.DraftTradeOffer) -> Int? {
        quote.userGetsPicks.first?.pickNumber
    }

    private func isOnTheClock(_ quote: DraftDayTradeEngine.DraftTradeOffer) -> Bool {
        guard let onClock = onTheClockPickNumber else { return false }
        return targetPickNumber(quote) == onClock
    }

    /// The on-the-clock quote first, everything else in the engine's order.
    /// A stable partition, not a sort: the rest of the list is already in
    /// ascending pick order and re-sorting it would renumber the board under a
    /// user who is reading it.
    private var orderedQuotes: [DraftDayTradeEngine.DraftTradeOffer] {
        let quotes = coordinator.tradeUpQuotes
        guard let idx = quotes.firstIndex(where: { isOnTheClock($0) }), idx != 0 else {
            return quotes
        }
        var reordered = quotes
        let live = reordered.remove(at: idx)
        reordered.insert(live, at: 0)
        return reordered
    }

    /// The quote the bar commits. Falls back to the first affordable line —
    /// usually the on-the-clock one — so the bar is never dead on arrival, and
    /// so a re-price that removes the chosen slot cannot strand the user with a
    /// primary pointed at a pick that is gone.
    private var selectedQuote: DraftDayTradeEngine.DraftTradeOffer? {
        let quotes = orderedQuotes
        if let selectedPickNumber,
           let match = quotes.first(where: { targetPickNumber($0) == selectedPickNumber }) {
            return match
        }
        return quotes.first(where: { $0.isAffordable }) ?? quotes.first
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let prospect = coordinator.tradeUpProspect {
                HStack(spacing: DSSpacing.sm) {
                    PersonFaceView(prospect: prospect, size: .small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Target: \(prospect.firstName) \(prospect.lastName)")
                            .font(DSType.text(DSType.Size.callout, .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("\(prospect.position.rawValue) \u{00B7} \(prospect.college)\(boardRankSuffix(prospect))")
                            .font(DSType.display(DSType.Size.caption, .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("Call the clubs picking ahead of you")
                    .font(DSType.text(DSType.Size.callout, .bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Toggle(isOn: Binding(
                get: { coordinator.tradeUpIncludesVeterans },
                set: { coordinator.setTradeUpIncludesVeterans($0) }
            )) {
                Text("Allow veterans in the package")
                    .font(DSType.text(DSType.Size.footnote, .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Color.accentGold)

            Text("Prices are the OTHER GM's, not the chart's \u{2014} an old-school front office sells at chart price, an analytics one barely sells at all.")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func boardRankSuffix(_ prospect: CollegeProspect) -> String {
        guard let rank = coordinator.publicBoardRanks[prospect.id] else { return "" }
        return " \u{00B7} Big Board #\(rank)"
    }

    // MARK: - Quote row

    /// One callable slot, as the app's list row rather than as a bespoke card:
    /// the pick number in the rank slot, the club in the position badge, the
    /// price in the identity block, the chart in a fixed column, and the choice
    /// in a radio column at the trailing edge.
    private func quoteRow(_ quote: DraftDayTradeEngine.DraftTradeOffer) -> some View {
        let season = coordinator.draftYear
        let pickNumber = targetPickNumber(quote)
        let isSelected = selectedQuote.map { targetPickNumber($0) == pickNumber } ?? false
        let live = isOnTheClock(quote)

        return Button {
            selectedPickNumber = pickNumber
        } label: {
            DSListRow(
                density: .study,
                rank: DSRank(
                    value: pickNumber ?? 0,
                    tint: quote.isAffordable ? Color.draftStealGold : Color.textTertiary
                ),
                badge: DSRowBadge(
                    text: quote.partnerAbbreviation,
                    tint: Color.backgroundTertiary,
                    accessibilityLabel: quote.partnerAbbreviation
                ),
                portraitWidth: 0
            ) {
                EmptyView()
            } identity: {
                VStack(alignment: .leading, spacing: 2) {
                    // Its own line, not inline with the price: the price is the
                    // longest string on the row and a pill sharing its line
                    // squeezes "2026 1st (#14) + 2027 2nd" into two.
                    if live {
                        DSStatusPill(label: "On the clock", tone: .warn, showsDot: false)
                    }
                    Text(quote.givesLabel(currentSeason: season))
                        .font(DSType.text(DSType.Size.body, .semibold))
                        .foregroundStyle(quote.isAffordable ? Color.textPrimary : Color.warning)
                        .lineLimit(2)
                    Text("\(quote.gmName) \u{00B7} \(quote.gmStyle)")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(quote.shortfall ?? quote.motive)
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(quote.shortfall == nil ? Color.textTertiary : Color.warning)
                        .lineLimit(2)
                }
                // The identity block is `DSListRow`'s flexible column but it
                // sizes to its content; without this the chart figures and the
                // radio would sit in the middle of a full-width sheet instead
                // of on its trailing edge.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, DSSpacing.xs)
            } columns: {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\u{2212}\(quote.userGivesValue)")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .foregroundStyle(Color.textSecondary)
                    Text("+\(quote.userGetsValue)")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .foregroundStyle(Color.draftStealGold)
                }
                .dsColumn(DSListColumn.money, alignment: .trailing)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
                    .dsColumn(DSListColumn.glyph)
            }
            .padding(.horizontal, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(
                                isSelected ? Color.accentGold : Color.surfaceBorder,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowSpoken(quote, live: live))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func rowSpoken(_ quote: DraftDayTradeEngine.DraftTradeOffer, live: Bool) -> String {
        let pick = targetPickNumber(quote).map { "Pick \($0)" } ?? "Pick"
        let clock = live ? ", on the clock now" : ""
        let price = quote.givesLabel(currentSeason: coordinator.draftYear)
        let gap = quote.isAffordable ? "" : ". \(quote.shortfall ?? "You cannot cover this")"
        return "\(pick) from \(quote.partnerAbbreviation)\(clock). Their price: \(price)\(gap)"
    }

    // MARK: - The one commit

    /// The screen's single gold fill. The explainer carries what the eight
    /// buttons used to try to carry in a 60 pt caption each: which slot, what it
    /// costs, and — on a quote he cannot cover — exactly what is missing.
    private var callActionBar: some View {
        let quote = selectedQuote
        let season = coordinator.draftYear
        let pickLabel = quote.flatMap { targetPickNumber($0) }.map { "#\($0)" } ?? "\u{2014}"
        let title: String = {
            guard let quote else { return "Nobody is picking up" }
            return "Move up to \(pickLabel) \u{00B7} \(quote.partnerAbbreviation)"
        }()
        let message: String = {
            guard let quote else {
                return "No club ahead of you will trade tonight. Close the phone and go back to the board."
            }
            if quote.isAffordable {
                return "You send **\(quote.givesLabel(currentSeason: season))** and get **\(quote.getsLabel(currentSeason: season))**."
            }
            return quote.shortfall ?? "You cannot cover this price with what you hold."
        }()
        return DSActionBar(
            explainer: .init(
                title: title,
                message: message,
                isWarning: quote?.isAffordable != true
            ),
            ghost: .init(
                title: "Back to the board",
                handler: { coordinator.closeTradeUpBoard() }
            ),
            primary: .init(
                title: "Make the call",
                caption: quote.map { "Chart: \u{2212}\($0.userGivesValue) \u{00B7} +\($0.userGetsValue) pts" },
                isEnabled: quote?.isAffordable == true,
                handler: {
                    guard let quote else { return }
                    coordinator.acceptTradeUpQuote(quote)
                }
            )
        )
    }
}
