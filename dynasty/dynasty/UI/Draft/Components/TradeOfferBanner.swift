import SwiftUI

/// Vaihe 3 placeholder. The trade offer engine work is partially complete on
/// the engine side, but the coordinator does not yet expose `pendingTradeOffer`.
/// This standalone banner renders an offer once the wiring lands; it is *not*
/// hooked into the live `DraftDayView` yet.
///
/// Visual contract: gold-bordered card, slides in from the top edge, presents
/// motive + outgoing/incoming asset summaries with Accept / Decline actions.
struct TradeOfferBanner: View {
    let motive: String
    let outgoing: String        // e.g. "#5 OVERALL"
    let incoming: String        // e.g. "#11 + 2027 2nd"
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var visible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "arrow.left.arrow.right.square.fill")
                    .foregroundStyle(Color.draftStealGold)
                Text("TRADE OFFER")
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(Color.draftStealGold)
                Spacer()
            }
            Text(motive)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DSSpacing.sm) {
                tradeColumn(title: "You Send", value: outgoing)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.textTertiary)
                tradeColumn(title: "You Receive", value: incoming)
            }
            HStack(spacing: DSSpacing.sm) {
                Button(role: .cancel) {
                    onDecline()
                } label: {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    onAccept()
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentGold)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.draftStealGold, lineWidth: 2)
                )
        )
        .shadow(color: Color.draftStealGold.opacity(0.5), radius: 12, x: 0, y: 4)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -40)
        .onAppear {
            withAnimation(.easeOut(duration: DraftAnimation.bannerIn)) {
                visible = true
            }
        }
    }

    private func tradeColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
