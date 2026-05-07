import SwiftUI

// MARK: - Workload Dashboard
//
// Heat-map style grid of every active player with their current
// workload status. 5-column grid (per screen width on iPad) with a
// position abbrev + emoji per cell. Tap a cell to drill in.

struct WorkloadDashboard: View {

    let roster: [Player]

    @State private var selectedPlayer: Player?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: DSSpacing.xs),
        count: 5
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                header
                legend
                grid
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Workload")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPlayer) { player in
            playerDetailSheet(for: player)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderText(title: "Workload Heat-Map")
            Text("Per-player camp load. Tap a cell for detail. Yellow / red flags signal injury risk.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legend: some View {
        HStack(spacing: DSSpacing.sm) {
            legendChip(color: Color.textTertiary, label: "Under-loaded")
            legendChip(color: Color.success, label: "Healthy")
            legendChip(color: Color.warning, label: "Over-loaded")
            legendChip(color: Color.danger, label: "Burned out")
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.xs) {
            ForEach(roster, id: \.id) { player in
                cell(for: player)
                    .onTapGesture { selectedPlayer = player }
            }
        }
    }

    private func cell(for player: Player) -> some View {
        let tint = tint(for: player.workloadStatus)
        return VStack(spacing: 2) {
            Text(player.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(player.workloadStatus.emoji)
                .font(.title3)
            Text(player.lastName)
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder(tint.opacity(0.7), lineWidth: 1)
        )
    }

    private func tint(for status: WorkloadStatus) -> Color {
        switch status {
        case .underloaded: return Color.textTertiary
        case .healthy:     return Color.success
        case .overloaded:  return Color.warning
        case .burnedOut:   return Color.danger
        }
    }

    // MARK: - Detail sheet

    private func playerDetailSheet(for player: Player) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.sm) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundTertiary)
                        )
                    VStack(alignment: .leading) {
                        Text(player.fullName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("OVR \(player.overall) · Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                statusRow(
                    label: "Status",
                    value: "\(player.workloadStatus.emoji) \(player.workloadStatus.rawValue.capitalized)",
                    tint: tint(for: player.workloadStatus)
                )
                statusRow(
                    label: "Cumulative load",
                    value: "\(player.cumulativeLoad) / 100",
                    tint: tint(for: player.workloadStatus)
                )
                statusRow(
                    label: "Injury multiplier",
                    value: String(format: "x%.1f", player.workloadStatus.injuryMultiplier),
                    tint: player.workloadStatus.injuryMultiplier > 1.0 ? Color.warning : Color.success
                )
                if let grade = player.campGrade {
                    statusRow(
                        label: "Camp grade",
                        value: grade.displayLabel,
                        tint: Color.accentGold
                    )
                }
                Spacer()
            }
            .padding(DSSpacing.md)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Workload Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func statusRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
    }
}
