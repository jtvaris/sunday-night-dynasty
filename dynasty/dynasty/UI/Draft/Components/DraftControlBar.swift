import SwiftUI

// MARK: - DraftControlBar — transport, and the room's one commit surface
//
// UI_REDESIGN_VISION P5 / §2.5. The war room already had "a genuine bottom
// control bar" (§3 family 8's own words) — it was just built out of bare
// `Button { } label: { Label(…) }`, i.e. tinted system text with no target box,
// no disabled state and no place for a commit to live.
//
// Two states, never both:
//
//   TRANSPORT   the default. Fast-forward, pause and speed: they change how
//               fast the broadcast runs and commit nothing, so they are ghost
//               and secondary buttons and there is NO gold on the bar.
//
//   DECISION    a rival GM is on the phone. The whole bar becomes a
//               `DSActionBar`: an explainer stating what the deal costs and
//               what it returns, then `[ghost Decline] [PRIMARY Accept]` in the
//               fixed order. This is the overlay reduction from §3 family 8 —
//               the offer used to float in over the board on the top edge as
//               one of five simultaneous overlay mechanisms, which is precisely
//               the "primary action in a place the screen does not own" defect
//               P5 exists to end.
//
// **Swapping rather than stacking is not a layout convenience.** The coordinator
// already stops the tape when a phone rings (`autoAdvanceUntil` breaks on
// `pendingTradeOffer != nil`), so there is nothing left for the transport
// controls to transport. A rail of live fast-forward buttons over a question the
// room is holding for you would be lying about the state it is in.

struct DraftControlBar: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        if let offer = coordinator.pendingTradeOffer, coordinator.mode != .userPick {
            decisionBar(for: offer)
        } else {
            transportRail
        }
    }

    // MARK: - Decision

    /// The explainer says WHO is calling and WHY; each button says what taking
    /// it leaves you holding, in chart points, on the control that produces that
    /// outcome. That is P4's cost→unlock line, split across the two answers
    /// instead of asserted once above them — the user compares the two captions
    /// rather than doing the subtraction himself.
    private func decisionBar(for offer: DraftDayTradeEngine.DraftTradeOffer) -> some View {
        let gives = offer.givesLabel(currentSeason: coordinator.draftYear)
        let gets = offer.getsLabel(currentSeason: coordinator.draftYear)
        return DSActionBar(
            explainer: .init(
                title: "Trade offer \u{2014} \(offer.gmName) \u{00B7} \(offer.gmStyle)",
                message: offer.motive
            ),
            ghost: .init(
                title: "Decline",
                caption: "Keep \(gives) \u{00B7} \(offer.userGivesValue) pts",
                handler: { coordinator.declineTradeOffer() }
            ),
            primary: .init(
                title: "Accept trade",
                caption: "Get \(gets) \u{00B7} \(offer.userGetsValue) pts",
                handler: { coordinator.acceptTradeOffer() }
            )
        )
    }

    // MARK: - Transport

    private var transportRail: some View {
        HStack(spacing: DSSpacing.xs) {
            Button { coordinator.skipToMyPick() } label: {
                Label("My pick", systemImage: "forward.end.fill")
            }
            .buttonStyle(.dsGhost)

            Button { coordinator.skipToNextEvent() } label: {
                Label("Next event", systemImage: "forward.fill")
            }
            .buttonStyle(.dsGhost)

            Button { coordinator.skipToNextRound() } label: {
                Label("Next round", systemImage: "forward.frame.fill")
            }
            .buttonStyle(.dsGhost)

            Spacer(minLength: DSSpacing.sm)

            if coordinator.mode == .paused {
                Button { coordinator.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.dsSecondary)
            } else {
                Button { coordinator.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.dsSecondary)
            }

            speedMenu
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
        .dsElevation(.bar)
    }

    /// Speed is a *setting*, not a commit, so it stays a menu — but it is a
    /// 44 pt one now (§2.12 has no exceptions) and it states its unit, because
    /// a bare "2" beside three transport buttons reads as a count of something.
    private var speedMenu: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { speed in
                Button(Self.label(for: speed)) { coordinator.setSpeed(speed) }
            }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "speedometer")
                Text(Self.label(for: coordinator.speed))
                    .font(DSType.display(14, .heavy))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, DSSpacing.md)
            .frame(minWidth: 88, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
            .dsElevation(.chip)
        }
        .accessibilityLabel("Broadcast speed, \(Self.label(for: coordinator.speed))")
    }

    private static let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]

    /// `Int(0.5)` is 0, so the old menu offered "0×" — a speed at which the
    /// draft does not happen.
    private static func label(for speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))\u{00D7}" : "\(speed)\u{00D7}"
    }
}
