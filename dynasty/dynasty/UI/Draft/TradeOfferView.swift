import SwiftUI

// MARK: - Draft Trade Asset

/// A lightweight display-only description of a single item in a draft trade offer.
struct DraftTradeAsset: Identifiable {
    let id: UUID
    let label: String       // e.g. "2026 1st Round Pick" or "Justin Fields"
    let detail: String?     // e.g. "Pick #5  ·  3000 pts" or "QB — 84 OVR"
    let value: Int          // Relative trade value (pick chart points)

    init(id: UUID = UUID(), label: String, detail: String? = nil, value: Int) {
        self.id = id
        self.label = label
        self.detail = detail
        self.value = value
    }
}

// MARK: - Draft Trade Offer Display

/// Display model for a single incoming trade offer presented to the player.
/// Distinct from the domain `TradeOffer` model used by the engine.
struct DraftTradeOfferDisplay: Identifiable {
    let id: UUID
    let offeringTeamName: String
    let offeringTeamAbbreviation: String
    /// Assets the AI team is sending to the player.
    let assetsOffered: [DraftTradeAsset]
    /// Assets the AI team wants in return (the player's assets).
    let assetsRequested: [DraftTradeAsset]
    /// The underlying domain model, kept for accept/decline processing.
    let domainOffer: TradeOffer

    init(
        id: UUID = UUID(),
        offeringTeamName: String,
        offeringTeamAbbreviation: String,
        assetsOffered: [DraftTradeAsset],
        assetsRequested: [DraftTradeAsset],
        domainOffer: TradeOffer
    ) {
        self.id = id
        self.offeringTeamName = offeringTeamName
        self.offeringTeamAbbreviation = offeringTeamAbbreviation
        self.assetsOffered = assetsOffered
        self.assetsRequested = assetsRequested
        self.domainOffer = domainOffer
    }

    var totalOfferedValue: Int { assetsOffered.reduce(0) { $0 + $1.value } }
    var totalRequestedValue: Int { assetsRequested.reduce(0) { $0 + $1.value } }

    /// Positive means the player receives more value than they give up.
    var valueDelta: Int { totalOfferedValue - totalRequestedValue }
}

// MARK: - TradeOfferView

/// Full-screen sheet presenting a single incoming trade offer for the player to accept or decline.
struct TradeOfferView: View {

    let offer: DraftTradeOfferDisplay
    let availableProspects: [CollegeProspect]
    let teamNeeds: [Position]
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        offerHeader
                        assetsSection(
                            title: "\(offer.offeringTeamName) sends you:",
                            assets: offer.assetsOffered,
                            accentColor: .success
                        )
                        assetsSection(
                            title: "They want from you:",
                            assets: offer.assetsRequested,
                            accentColor: .danger
                        )
                        valueComparisonCard
                        strategicContextCard
                        actionButtons
                    }
                    .padding(24)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Trade Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        onDecline()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Offer Header

    private var offerHeader: some View {
        VStack(spacing: 10) {
            Text(offer.offeringTeamAbbreviation)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 64, height: 64)
                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 12))

            Text(offer.offeringTeamName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)

            Text("wants to make a trade")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Assets Section

    private func assetsSection(
        title: String,
        assets: [DraftTradeAsset],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: 18)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(spacing: 8) {
                ForEach(assets) { asset in
                    assetRow(asset, accentColor: accentColor)
                }
            }

            HStack {
                Spacer()
                Text("Total: \(formatValue(assets.reduce(0) { $0 + $1.value }))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func assetRow(_ asset: DraftTradeAsset, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                if let detail = asset.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            Text(formatValue(asset.value))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary)
        )
    }

    // MARK: - Value Comparison Card

    private var valueComparisonCard: some View {
        VStack(spacing: 14) {
            Text("Trade Value Comparison")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            // Compact summary line
            tradeValueSummaryLine

            // Value bar
            GeometryReader { geo in
                let total = max(offer.totalOfferedValue + offer.totalRequestedValue, 1)
                let offeredFraction = CGFloat(offer.totalOfferedValue) / CGFloat(total)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.danger.opacity(0.3))
                        .frame(height: 16)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.success)
                        .frame(width: geo.size.width * offeredFraction, height: 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 16)

            // Labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You receive")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(formatValue(offer.totalOfferedValue))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.success)
                }

                Spacer()

                VStack(alignment: .center, spacing: 2) {
                    let delta = offer.valueDelta
                    Text(delta >= 0 ? "WIN" : "LOSS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(delta >= 0 ? Color.success : Color.danger)
                    Text("\(delta >= 0 ? "+" : "")\(formatValue(delta))")
                        .font(.callout.weight(.heavy).monospacedDigit())
                        .foregroundStyle(delta >= 0 ? Color.success : Color.danger)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("You give up")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(formatValue(offer.totalRequestedValue))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.danger)
                }
            }

            // Fairness indicator
            tradeValueFairnessIndicator
        }
        .padding(16)
        .cardBackground()
    }

    /// One-line summary: "Their offer: X pts | Your pick value: Y pts | Difference: Z"
    private var tradeValueSummaryLine: some View {
        let delta = offer.valueDelta
        let deltaColor: Color = delta >= 0 ? .success : .danger
        let deltaSign = delta >= 0 ? "+" : ""

        return HStack(spacing: 6) {
            Text("Their offer:")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Text(formatValue(offer.totalOfferedValue))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.success)

            Text("|")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            Text("Your pick value:")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Text(formatValue(offer.totalRequestedValue))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.danger)

            Text("|")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            Text("Diff: \(deltaSign)\(formatValue(delta))")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(deltaColor)
        }
    }

    /// Shows whether the trade is considered fair based on the 15% threshold.
    private var tradeValueFairnessIndicator: some View {
        let offeringPicks = offer.assetsOffered.map(\.value)
        let receivingPicks = offer.assetsRequested.map(\.value)
        let evaluation = DraftEngine.evaluateTradeValue(
            offering: offeringPicks,
            receiving: receivingPicks
        )
        let delta = offer.valueDelta

        return HStack(spacing: 8) {
            Image(systemName: evaluation.isFair ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(evaluation.isFair ? Color.success : (delta >= 0 ? Color.success : Color.danger))

            Text(evaluation.isFair
                 ? "Fair trade — values within 15%"
                 : (delta >= 0 ? "Great deal for you" : "Bad deal — you are overpaying"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(evaluation.isFair ? Color.success : (delta >= 0 ? Color.success : Color.danger))

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((evaluation.isFair ? Color.success : (delta >= 0 ? Color.success : Color.danger)).opacity(0.08))
        )
    }

    // MARK: - Strategic Context Card

    private var strategicContextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentGold)
                Text("Strategic Analysis")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }

            Divider().overlay(Color.surfaceBorder)

            // Show likely available prospects at the new pick position
            if let newPickNumber = offer.assetsOffered.first.flatMap({ extractPickNumber($0) }) {
                let likelyAvailable = prospectsLikelyAvailable(at: newPickNumber)
                if !likelyAvailable.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("At pick #\(newPickNumber), likely available:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)

                        ForEach(likelyAvailable, id: \.id) { prospect in
                            HStack(spacing: 8) {
                                Text(prospect.position.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                    .frame(width: 30, height: 20)
                                    .background(prospectPositionColor(prospect.position), in: RoundedRectangle(cornerRadius: 4))
                                Text(prospect.fullName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if let ovr = prospect.scoutedOverall {
                                    Text("\(ovr)")
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Color.forRating(ovr))
                                }
                            }
                        }
                    }
                }

                // Needs impact analysis
                if !teamNeeds.isEmpty {
                    Divider().overlay(Color.surfaceBorder)
                    needsImpactView(newPickNumber: newPickNumber)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Estimates which top prospects might still be available at the given pick number.
    private func prospectsLikelyAvailable(at pickNumber: Int) -> [CollegeProspect] {
        // Use mock draft pick numbers to estimate who will be gone
        let sorted = availableProspects
            .filter { $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }

        // Prospects with a mock draft pick number at or after this pick are likely available
        let likelyAvailable = sorted.filter { prospect in
            if let mockPick = prospect.mockDraftPickNumber {
                return mockPick >= pickNumber - 3 // Allow some variance
            }
            // If no mock data, use projection round
            if let projRound = prospect.draftProjection {
                let projMinPick = (projRound - 1) * 32 + 1
                return projMinPick >= pickNumber - 10
            }
            return true // Unranked prospects likely available
        }

        return Array(likelyAvailable.prefix(3))
    }

    /// Shows how trading affects your top positional needs.
    @ViewBuilder
    private func needsImpactView(newPickNumber: Int) -> some View {
        let topNeed = teamNeeds.first
        let likelyAvailable = prospectsLikelyAvailable(at: newPickNumber)
        let topNeedStillAvailable = topNeed.map { need in
            likelyAvailable.contains { $0.position == need }
        } ?? false

        VStack(alignment: .leading, spacing: 6) {
            Text("Needs Impact")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            if let topNeed {
                if topNeedStillAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.success)
                        Text("Top \(topNeed.rawValue) prospect likely still available at #\(newPickNumber)")
                            .font(.caption)
                            .foregroundStyle(Color.success)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.warning)
                        Text("Moving to #\(newPickNumber) -- top \(topNeed.rawValue) prospect likely gone by then")
                            .font(.caption)
                            .foregroundStyle(Color.warning)
                    }
                }
            }

            // Show which needs might still be addressable
            let addressableNeeds = teamNeeds.prefix(3).filter { need in
                likelyAvailable.contains { $0.position == need }
            }
            if !addressableNeeds.isEmpty {
                HStack(spacing: 4) {
                    Text("Addressable needs:")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(addressableNeeds, id: \.self) { pos in
                        Text(pos.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.success.opacity(0.12))
                            )
                    }
                }
            }
        }
    }

    /// Extracts the pick number from a trade asset's detail string.
    private func extractPickNumber(_ asset: DraftTradeAsset) -> Int? {
        // Parse "Pick #42  ·  580 pts" format
        let detail = asset.detail ?? ""
        if let range = detail.range(of: "#") {
            let afterHash = detail[range.upperBound...]
            let digits = afterHash.prefix(while: { $0.isNumber })
            return Int(digits)
        }
        return nil
    }

    private func prospectPositionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 14) {
            // Decline
            Button {
                onDecline()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Decline")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.backgroundTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Accept
            Button {
                onAccept()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Accept Trade")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentGold)
                        .shadow(color: Color.accentGold.opacity(0.4), radius: 10, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func formatValue(_ value: Int) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fK pts", Double(value) / 1000.0)
        }
        return "\(value) pts"
    }
}

// MARK: - Preview

#Preview {
    let domainOffer = TradeOffer(
        offeringTeamID: UUID(),
        receivingTeamID: UUID(),
        picksSending: [],
        picksReceiving: []
    )
    TradeOfferView(
        offer: DraftTradeOfferDisplay(
            offeringTeamName: "New England Patriots",
            offeringTeamAbbreviation: "NE",
            assetsOffered: [
                DraftTradeAsset(label: "2026 2nd Round Pick", detail: "Pick #42  ·  580 pts", value: 580),
                DraftTradeAsset(label: "2027 3rd Round Pick", detail: "Projected mid-round  ·  145 pts", value: 145),
            ],
            assetsRequested: [
                DraftTradeAsset(label: "2026 1st Round Pick", detail: "Pick #5  ·  1700 pts", value: 1700),
            ],
            domainOffer: domainOffer
        ),
        availableProspects: [],
        teamNeeds: [.CB, .DE, .SS],
        onAccept: {},
        onDecline: {}
    )
}
