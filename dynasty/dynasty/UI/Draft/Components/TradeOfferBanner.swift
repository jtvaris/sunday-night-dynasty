import SwiftUI

/// Draft-day trade offer banner (wired to `pendingTradeOffer`).
///
/// Visual contract: gold-bordered card, slides in from the top edge, presents
/// the GM who called + his motive + outgoing/incoming asset summaries with
/// Accept / Decline actions. Since Wave 4 the assets on either side can be
/// picks (this year's or a future one) or veterans, so the columns render
/// whatever string the offer hands them.
struct TradeOfferBanner: View {
    let motive: String
    let outgoing: String        // e.g. "#5 (R1)"
    let incoming: String        // e.g. "#11 (R1) + 2028 R1"
    /// "Ray Pellman · Analytics" — who is on the other end of the phone.
    var gmLine: String? = nil
    var valueSummary: String? = nil   // e.g. "you send 1100 pts · receive 1180 pts"
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
                if let gmLine {
                    Text(gmLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(motive)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DSSpacing.sm) {
                tradeColumn(title: "You Send", value: outgoing)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.textTertiary)
                tradeColumn(title: "You Receive", value: incoming)
            }
            if let valueSummary {
                Text(valueSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.textSecondary)
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
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
