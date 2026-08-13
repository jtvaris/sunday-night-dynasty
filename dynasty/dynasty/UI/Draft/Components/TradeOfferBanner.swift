import SwiftUI

// MARK: - TradeOfferBanner — the offer card, INSIDE a surface that owns it
//
// #105 Wave 3b changed what this component is. It used to be one of the war
// room's five simultaneous overlay mechanisms: a gold-bordered card floating in
// over the board on the top edge, carrying the screen's only two commit buttons
// in a place the screen did not own. That is P5's headline defect, and the room
// version is gone — `DraftControlBar` raises the same offer as a `DSActionBar`
// at the bottom, where every other commit in the app lives.
//
// Its one remaining call site was `PickSheetView`, which presented the card
// inline in its own scroll body while the user was on the clock. **#197 retired
// that sheet, so this component currently has NO call site.** It is kept, and
// only kept, because the rule it encodes is still the room's rule — a card
// inside a surface that owns the screen is a card; the same card floating over
// the board is an overlay mechanism — and any future inline offer surface must
// be this one rather than a sixth hand-rolled banner.
//
// An offer arriving while the user is on the clock is answered on
// `DraftControlBar`: its `stance` now gives the bar to the phone in every mode,
// which is what stopped #197 from making such an offer unanswerable.
//
// If nothing has adopted it by the next dead-code sweep, delete the file.
//
// Restyled onto the shared vocabulary: `DSType`'s two voices, `.dsGhost` /
// `.dsPrimary` (the 44 pt, genuinely-disabled-grey set), and one accent instead
// of `draftStealGold` on the border, the icon, the eyebrow and the button tint —
// which was four gold jobs in one card, on a hue that has three in the whole app.

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
            header
            Text(motive)
                .font(DSType.text(14, .regular, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                tradeColumn(title: "You send", value: outgoing)
                Image(systemName: "arrow.right")
                    .font(DSType.display(14, .heavy))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .padding(.top, DSSpacing.md)
                tradeColumn(title: "You receive", value: incoming)
            }
            if let valueSummary {
                Text(valueSummary)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DSSpacing.xs) {
                Spacer(minLength: 0)
                Button("Decline", action: onDecline)
                    .buttonStyle(.dsGhost)
                Button("Accept trade", action: onAccept)
                    .buttonStyle(.dsPrimary)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.accentBlue.opacity(0.55), lineWidth: 1)
        )
        .dsElevation(.card)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -24)
        .onAppear {
            withAnimation(.easeOut(duration: DraftAnimation.bannerIn)) {
                visible = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "arrow.left.arrow.right")
                .font(DSType.display(11, .black))
                .foregroundStyle(Color.accentBlue)
            Text("TRADE OFFER")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.accentBlue)
            Spacer(minLength: DSSpacing.xs)
            if let gmLine {
                Text(gmLine)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func tradeColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textTertiaryReadable)
            Text(value)
                .font(DSType.text(16, .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
