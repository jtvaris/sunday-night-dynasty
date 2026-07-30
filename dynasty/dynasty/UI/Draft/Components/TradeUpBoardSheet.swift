import SwiftUI

/// "Call about moving up" — the draft room's phone.
///
/// Wave 4 (plan §6 Wave 4 / finding S6: "no user trade-UP path exists at all",
/// the most-wanted GM move). Every callable slot ahead of the user is priced by
/// the club that owns it — his persona's hidden chart lean, his stance and his
/// needs — and answered with the best package the user can actually assemble.
/// Unaffordable quotes stay on the list with the gap spelled out, because "here
/// is the price and here is what you're missing" is the useful answer.
struct TradeUpBoardSheet: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                header

                if let message = coordinator.tradeUpMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Color.warning)
                        .padding(.vertical, DSSpacing.sm)
                }

                ScrollView {
                    LazyVStack(spacing: DSSpacing.sm) {
                        ForEach(coordinator.tradeUpQuotes) { quote in
                            quoteCard(quote)
                        }
                    }
                    .padding(.bottom, DSSpacing.md)
                }
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.backgroundPrimary)
            .navigationTitle("Trade Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { coordinator.closeTradeUpBoard() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let prospect = coordinator.tradeUpProspect {
                HStack(spacing: DSSpacing.sm) {
                    PersonFaceView(prospect: prospect, size: .small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Target: \(prospect.firstName) \(prospect.lastName)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("\(prospect.position.rawValue) · \(prospect.college)\(boardRankSuffix(prospect))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("Call the clubs picking ahead of you")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Toggle(isOn: Binding(
                get: { coordinator.tradeUpIncludesVeterans },
                set: { coordinator.setTradeUpIncludesVeterans($0) }
            )) {
                Text("Allow veterans in the package")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Color.accentGold)

            Text("Prices are the OTHER GM's, not the chart's — an old-school front office sells at chart price, an analytics one barely sells at all.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func boardRankSuffix(_ prospect: CollegeProspect) -> String {
        guard let rank = coordinator.publicBoardRanks[prospect.id] else { return "" }
        return " · Big Board #\(rank)"
    }

    // MARK: - Quote card

    private func quoteCard(_ quote: DraftDayTradeEngine.DraftTradeOffer) -> some View {
        let season = coordinator.draftYear
        let target = quote.userGetsPicks.first

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Text(target.map { "#\($0.pickNumber)" } ?? "—")
                    .font(.title3.monospaced().weight(.heavy))
                    .foregroundStyle(quote.isAffordable ? Color.draftStealGold : Color.textTertiary)
                Text(quote.partnerAbbreviation)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(quote.gmName) · \(quote.gmStyle)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Their price: \(quote.givesLabel(currentSeason: season))")
                .font(.callout.weight(.semibold))
                .foregroundStyle(quote.isAffordable ? Color.textPrimary : Color.warning)
                .fixedSize(horizontal: false, vertical: true)

            Text("Chart: you send \(quote.userGivesValue) pts · receive \(quote.userGetsValue) pts")
                .font(.caption2.monospaced())
                .foregroundStyle(Color.textSecondary)

            if let shortfall = quote.shortfall {
                Label(shortfall, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.warning)
            }

            HStack {
                Text(quote.motive)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    coordinator.acceptTradeUpQuote(quote)
                } label: {
                    Text(quote.isAffordable ? "MAKE THE CALL" : "CAN'T COVER")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(quote.isAffordable ? Color.accentGold : Color.backgroundTertiary)
                .disabled(!quote.isAffordable)
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(
                            quote.isAffordable ? Color.draftStealGold.opacity(0.7) : Color.surfaceBorder,
                            lineWidth: quote.isAffordable ? 2 : 1
                        )
                )
        )
    }
}
