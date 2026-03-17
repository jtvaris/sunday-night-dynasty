import SwiftUI
import SwiftData

// MARK: - Versatility Rating

/// How naturally a player can operate at an alternate position.
enum VersatilityRating: Int, Comparable, CaseIterable {
    case natural      = 4  // Primary position
    case accomplished = 3  // Very capable
    case competent    = 2  // Playable with some drops
    case unconvincing = 1  // Significant drops
    case unqualified  = 0  // Not viable

    static func < (lhs: VersatilityRating, rhs: VersatilityRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .natural:      return "Natural"
        case .accomplished: return "Accomplished"
        case .competent:    return "Competent"
        case .unconvincing: return "Unconvincing"
        case .unqualified:  return "Unqualified"
        }
    }

    var shortLabel: String {
        switch self {
        case .natural:      return "NAT"
        case .accomplished: return "ACC"
        case .competent:    return "COM"
        case .unconvincing: return "UNC"
        case .unqualified:  return "---"
        }
    }

    var color: Color {
        switch self {
        case .natural:      return .accentGold
        case .accomplished: return .success
        case .competent:    return .accentBlue
        case .unconvincing: return .warning
        case .unqualified:  return .backgroundTertiary
        }
    }

    var textColor: Color {
        switch self {
        case .unqualified: return .textTertiary
        default:           return .textPrimary
        }
    }
}

// MARK: - VersatilityEngine (Local Logic)

/// Pure-function logic for computing position versatility from player attributes.
private enum VersatilityEngine {

    /// Returns all positions where a player has at least Unconvincing viability.
    static func viablePositions(for player: Player) -> [(Position, VersatilityRating)] {
        Position.allCases
            .compactMap { pos -> (Position, VersatilityRating)? in
                let rating = rate(player: player, at: pos)
                guard rating != .unqualified else { return nil }
                return (pos, rating)
            }
            .sorted { $0.1 > $1.1 }
    }

    /// Computes the versatility rating for a player at the given position.
    static func rate(player: Player, at position: Position) -> VersatilityRating {
        if player.position == position { return .natural }

        let speed = player.physical.speed
        let strength = player.physical.strength
        let agility = player.physical.agility
        let awareness = player.mental.awareness
        let leadership = player.mental.leadership

        switch (player.position, position) {

        // --- Offensive Line Interoperability ---
        case (.LT, .LG), (.LT, .RT),
             (.RT, .RG), (.RT, .LT),
             (.LG, .LT), (.LG, .C), (.LG, .RG),
             (.RG, .LG), (.RG, .C), (.RG, .RT),
             (.C, .LG), (.C, .RG):
            return strength > 75 && agility > 60 ? .accomplished : .competent

        case (.LT, .C), (.RT, .C):
            return strength > 70 && awareness > 70 ? .competent : .unconvincing

        case (.LT, .RG), (.LT, .LG) where strength < 70:
            return .unconvincing

        // --- WR <-> TE ---
        case (.WR, .TE):
            return speed > 75 && strength > 65 ? .competent : .unconvincing
        case (.TE, .WR):
            return speed > 70 && agility > 68 ? .competent : .unconvincing

        // --- RB <-> FB ---
        case (.RB, .FB):
            return strength > 65 ? .accomplished : .competent
        case (.FB, .RB):
            return speed > 72 && agility > 68 ? .competent : .unconvincing

        // --- Safety Interoperability ---
        case (.FS, .SS):
            return speed > 72 && strength > 60 ? .accomplished : .competent
        case (.SS, .FS):
            return speed > 75 && awareness > 70 ? .competent : .unconvincing

        // --- CB <-> Safety ---
        case (.CB, .FS):
            return speed > 80 && awareness > 70 ? .competent : .unconvincing
        case (.CB, .SS):
            return speed > 75 && strength > 65 ? .competent : .unconvincing
        case (.FS, .CB), (.SS, .CB):
            return speed > 80 ? .unconvincing : .unqualified

        // --- LB Interoperability ---
        case (.OLB, .MLB):
            return strength > 72 && awareness > 68 ? .competent : .unconvincing
        case (.MLB, .OLB):
            return speed > 68 && agility > 65 ? .competent : .unconvincing

        // --- DE <-> OLB (3-4/4-3 conversions) ---
        case (.DE, .OLB):
            return speed > 75 && agility > 65 ? .competent : .unconvincing
        case (.OLB, .DE):
            return strength > 75 && speed > 68 ? .competent : .unconvincing

        // --- DE <-> DT ---
        case (.DE, .DT):
            return strength > 78 ? .unconvincing : .unqualified
        case (.DT, .DE):
            return speed > 68 && agility > 65 ? .unconvincing : .unqualified

        // --- QB to WR? Classic trick play ---
        case (.QB, .WR):
            return speed > 75 && agility > 72 ? .unconvincing : .unqualified

        // --- Leadership-based position flexibility ---
        // Veteran leaders can sometimes contribute at hybrid roles
        case _ where leadership > 85 && player.position.side == position.side:
            return .unconvincing

        default:
            return .unqualified
        }
    }
}

// MARK: - PositionVersatilityView

/// Matrix/grid showing each rostered player's versatility across NFL positions.
struct PositionVersatilityView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var players: [Player] = []
    @State private var selectedPlayer: Player? = nil
    @State private var showTrainAlert = false
    @State private var trainTargetPosition: Position? = nil
    @State private var selectedSide: PositionSide? = .offense

    // MARK: - Filtered Players

    private var displayPlayers: [Player] {
        guard let side = selectedSide else { return players }
        return players.filter { $0.position.side == side }
    }

    // MARK: - Positions to Show in Matrix

    private var matrixPositions: [Position] {
        guard let side = selectedSide else { return Position.allCases }
        return Position.allCases.filter { $0.side == side }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    legendCard
                    sideFilter
                    if let selected = selectedPlayer {
                        playerDetailCard(selected)
                    }
                    matrixCard
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Position Versatility")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadPlayers() }
        .alert("Start Position Training", isPresented: $showTrainAlert) {
            Button("Begin Training") {
                // Training engine integration point
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let player = selectedPlayer, let pos = trainTargetPosition {
                Text("Train \(player.fullName) at \(pos.rawValue)? This is a slow conversion process that takes multiple seasons to show results.")
            }
        }
    }

    // MARK: - Legend Card

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Versatility Ratings")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 8) {
                ForEach(VersatilityRating.allCases.reversed(), id: \.rawValue) { rating in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rating.color)
                            .frame(width: 26, height: 20)
                            .overlay(
                                Text(rating.shortLabel)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(rating.textColor)
                            )
                        Text(rating.label)
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if rating != .unqualified {
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Side Filter

    private var sideFilter: some View {
        Picker("Unit", selection: $selectedSide) {
            Text("Offense").tag(Optional<PositionSide>.some(.offense))
            Text("Defense").tag(Optional<PositionSide>.some(.defense))
            Text("Spec. Teams").tag(Optional<PositionSide>.some(.specialTeams))
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Player Detail Card

    private func playerDetailCard(_ player: Player) -> some View {
        let viablePositions = VersatilityEngine.viablePositions(for: player)
            .filter { $0.0 != player.position }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                positionBadge(player.position, large: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text("Primary: \(player.position.rawValue) · Age \(player.age) · \(player.overall) OVR")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button {
                    selectedPlayer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Color.surfaceBorder)

            if viablePositions.isEmpty {
                Text("No alternative positions available for this player.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text("Alternative Positions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                FlowLayout(spacing: 8) {
                    ForEach(viablePositions, id: \.0) { pos, rating in
                        Button {
                            trainTargetPosition = pos
                            showTrainAlert = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(pos.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(rating.label)
                                    .font(.caption2)
                                    .foregroundStyle(rating.color)
                                Image(systemName: "arrow.clockwise.circle")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentBlue)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(rating.color.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(rating.color.opacity(0.4), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pos.rawValue), \(rating.label). Tap to train at this position.")
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Matrix Card

    private var matrixCard: some View {
        VStack(spacing: 0) {
            // Column headers (positions)
            matrixHeaderRow

            Divider().overlay(Color.surfaceBorder)

            // Player rows
            if displayPlayers.isEmpty {
                Text("No players on roster.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(displayPlayers.enumerated()), id: \.element.id) { idx, player in
                    matrixRow(player)

                    if idx < displayPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.4))
                    }
                }
            }
        }
        .cardBackground()
    }

    private var matrixHeaderRow: some View {
        HStack(spacing: 0) {
            // Player name header
            Text("Player")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 160, alignment: .leading)
                .padding(.leading, 16)

            // Position column headers
            ForEach(matrixPositions) { pos in
                Text(pos.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            // Train button column
            Text("Train")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 60)
                .padding(.trailing, 12)
        }
        .frame(height: 36)
    }

    private func matrixRow(_ player: Player) -> some View {
        let isSelected = selectedPlayer?.id == player.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlayer = isSelected ? nil : player
            }
        } label: {
            HStack(spacing: 0) {
                // Player info
                HStack(spacing: 8) {
                    positionBadge(player.position, large: false)
                    Text(player.fullName)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 160, alignment: .leading)
                .padding(.leading, 16)

                // Rating cells
                ForEach(matrixPositions) { pos in
                    ratingCell(player: player, position: pos)
                }

                // Best alternative indicator
                bestAlternativeTrainButton(player)
            }
            .frame(height: 44)
            .background(isSelected ? Color.accentGold.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.fullName), tap to see versatility details")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func ratingCell(player: Player, position: Position) -> some View {
        let rating = VersatilityEngine.rate(player: player, at: position)

        return ZStack {
            Rectangle()
                .fill(rating == .unqualified ? Color.clear : rating.color.opacity(0.18))

            Text(rating.shortLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(rating == .unqualified ? Color.backgroundTertiary : rating.color)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .accessibilityLabel("\(position.rawValue): \(rating.label)")
    }

    private func bestAlternativeTrainButton(_ player: Player) -> some View {
        let best = VersatilityEngine.viablePositions(for: player)
            .filter { $0.0 != player.position }
            .max { $0.1 < $1.1 }

        return Group {
            if let (pos, _) = best {
                Button {
                    selectedPlayer = player
                    trainTargetPosition = pos
                    showTrainAlert = true
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.accentBlue)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .frame(width: 60)
                .padding(.trailing, 12)
                .accessibilityLabel("Train \(player.fullName) at \(pos.rawValue)")
            } else {
                Color.clear
                    .frame(width: 60)
                    .padding(.trailing, 12)
            }
        }
    }

    // MARK: - Helpers

    private func loadPlayers() {
        guard let teamID = career.teamID else { return }
        var descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        descriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func positionBadge(_ position: Position, large: Bool) -> some View {
        Text(position.rawValue)
            .font(.system(size: large ? 11 : 9, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: large ? 34 : 26)
            .padding(.vertical, large ? 4 : 3)
            .background(positionSideColor(position), in: RoundedRectangle(cornerRadius: 3))
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - FlowLayout

/// A simple wrapping horizontal layout for chips/badges.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight

        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PositionVersatilityView(
            career: Career(playerName: "Coach Smith", role: .gm, capMode: .simple)
        )
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
