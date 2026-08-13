import SwiftUI

// MARK: - Shared Trade Asset Widgets (Wave 3)
//
// The two-column "You send / You receive" widget was born inside `TradeView`'s
// incoming-offer card. Wave 3's negotiation transcript needs exactly the same
// thing inside every message bubble — an offer the GM made three weeks ago has
// to read like an offer — so it moves here and both screens draw the same
// component. One widget means the snapshot in the thread and the card in the
// Trade Center can never drift into showing the same deal two ways.

// MARK: - Formatting

enum TradeAssetFormat {

    /// Compact pick label, e.g. `2027 2nd (#48)`.
    ///
    /// A future pick's number is a round-midpoint placeholder until
    /// `adoptFuturePicks` renumbers it from real standings — quoting it would
    /// invent precision the league doesn't have yet.
    /// #152: the year PRINTED is `DraftPick.displayDraftYear`, never the stored
    /// `seasonYear`. The draft room, the war room and this label all have to
    /// name the same pick the same way, and the draft is named for the season
    /// its rookies debut in — see `DraftYearLabel`.
    static func pickLabelShort(_ pick: DraftPick) -> String {
        let suffix: String
        switch pick.round {
        case 1: suffix = "1st"
        case 2: suffix = "2nd"
        case 3: suffix = "3rd"
        default: suffix = "\(pick.round)th"
        }
        if pick.isProvisionalOrder {
            return "\(pick.displayDraftYear) \(suffix)"
        }
        return "\(pick.displayDraftYear) \(suffix) (#\(pick.pickNumber))"
    }

    /// Long pick label used by the builder rows.
    static func pickLabel(_ pick: DraftPick) -> String {
        let suffix: String
        switch pick.round {
        case 1: suffix = "1st"
        case 2: suffix = "2nd"
        case 3: suffix = "3rd"
        default: suffix = "\(pick.round)th"
        }
        if pick.isProvisionalOrder {
            return "\(pick.displayDraftYear) \(suffix) Rd"
        }
        return "\(pick.displayDraftYear) \(suffix) Rd (#\(pick.pickNumber))"
    }

    static func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - Asset Column

/// One side of a deal: a titled list of players and picks with a point total.
struct TradeAssetColumn: View {

    let title: String
    let players: [Player]
    let picks: [DraftPick]
    let valueLabel: String
    let accentColor: Color
    /// Every name in an offer is tappable in the Trade Center — judging "is this
    /// a good deal?" means reading the player. Inside a transcript bubble the
    /// rows stay flat: a snapshot is a record, not a menu.
    var showsDetailLinks: Bool = true
    /// Tighter type for the in-bubble snapshot.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(valueLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
            }

            ForEach(players) { player in
                if showsDetailLinks {
                    NavigationLink(destination: PlayerDetailView(player: player)) {
                        playerRow(player, chevron: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    playerRow(player, chevron: false)
                }
            }

            ForEach(picks) { pick in
                HStack(spacing: 6) {
                    Text("PICK")
                        .font(.system(size: DSType.Size.caption).weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                    Text(TradeAssetFormat.pickLabelShort(pick))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
            }

            if players.isEmpty && picks.isEmpty {
                Text("Nothing")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerRow(_ player: Player, chevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.caption).weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    TradeAssetFormat.positionColor(player.position),
                    in: RoundedRectangle(cornerRadius: 3)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(player.overall) OVR · Age \(player.age)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

// MARK: - Offer Snapshot Card

/// The frozen package attached to one line of a negotiation transcript.
///
/// Always drawn from the USER's perspective — left column is what leaves the
/// building, right column is what arrives — no matter who said the line. A
/// transcript that flips its columns depending on the speaker is unreadable.
struct TradeOfferSnapshotCard: View {

    let sendPlayers: [Player]
    let sendPicks: [DraftPick]
    let receivePlayers: [Player]
    let receivePicks: [DraftPick]
    let sendValue: Int
    let receiveValue: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TradeAssetColumn(
                title: "You send",
                players: sendPlayers,
                picks: sendPicks,
                valueLabel: "\(sendValue) pts",
                accentColor: Color.accentBlue,
                showsDetailLinks: false,
                compact: true
            )
            Divider()
                .overlay(Color.surfaceBorder)
                .frame(maxHeight: 160)
            TradeAssetColumn(
                title: "You receive",
                players: receivePlayers,
                picks: receivePicks,
                valueLabel: "\(receiveValue) pts",
                accentColor: Color.accentGold,
                showsDetailLinks: false,
                compact: true
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundPrimary.opacity(0.55))
        )
    }
}

// MARK: - Asset Toggle Row

/// A selectable asset in the package editor. Shared so the Trade Center builder
/// and the mid-negotiation editor tick assets identically.
struct TradeAssetToggleRow: View {

    let label: String
    let sublabel: String
    let valueLabel: String
    let isSelected: Bool
    let accentColor: Color
    /// Why this asset cannot legally be in a package at all (#141b).
    ///
    /// A league rule that depends only on the asset — a franchise tag today —
    /// has to refuse the tap, not decorate the Propose button. The old flow let
    /// a tagged man be checked, counted him into "You Send" and only then
    /// printed "Franchise-tagged players can't be traded." next to a Propose
    /// button that still looked live. Non-nil disables the row and states the
    /// rule where the mistake is made.
    var blockedReason: String? = nil
    let action: () -> Void

    private var isBlocked: Bool { blockedReason != nil }

    var body: some View {
        Button(action: { if !isBlocked { action() } }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: isBlocked
                          ? "lock.fill"
                          : (isSelected ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(isBlocked
                                         ? Color.textTertiary
                                         : (isSelected ? accentColor : Color.textTertiary))
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isBlocked ? Color.textTertiary : Color.textPrimary)
                            .lineLimit(1)
                        Text(sublabel)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text(valueLabel)
                        .font(.system(size: 10).weight(.semibold).monospacedDigit())
                        .foregroundStyle(isBlocked
                                         ? Color.textTertiary
                                         : (isSelected ? accentColor : Color.textSecondary))
                }

                if let blockedReason {
                    Text(blockedReason)
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 24)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected && !isBlocked
                          ? accentColor.opacity(0.12)
                          : Color.backgroundTertiary)
            )
            .opacity(isBlocked ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .accessibilityHint(blockedReason ?? "")
    }
}
