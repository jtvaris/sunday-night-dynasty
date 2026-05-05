import SwiftUI

struct PickSheetView: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let pick = coordinator.currentPick {
                    Text("Pick #\(pick.pickNumber) (Round \(pick.round))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("⏱ \(coordinator.clockSeconds) seconds remaining")
                        .font(.callout)
                        .foregroundStyle(coordinator.clockSeconds <= 30 ? Color.draftClockUrgent : Color.textSecondary)
                }
                Divider().overlay(Color.surfaceBorder)
                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(topProspects, id: \.id) { prospect in
                            prospectButton(prospect)
                        }
                    }
                }
            }
            .padding(DSSpacing.lg)
            .background(Color.backgroundPrimary)
            .navigationTitle("Make Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var topProspects: [CollegeProspect] {
        Array(
            coordinator.availableProspects
                .sorted { ($0.draftProjection ?? 999) < ($1.draftProjection ?? 999) }
                .prefix(20)
        )
    }

    private func prospectButton(_ prospect: CollegeProspect) -> some View {
        Button {
            coordinator.selectProspect(prospect)
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prospect.firstName) \(prospect.lastName)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(prospect.position.rawValue) · \(prospect.college) · OVR \(prospect.trueOverall)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if let bb = prospect.draftProjection {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("BB #\(bb)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                        if let pick = coordinator.currentPick {
                            let delta = pick.pickNumber - bb
                            Text(delta >= 0 ? "STEAL +\(delta)" : "REACH \(delta)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(delta >= 0 ? Color.success : Color.warning)
                        }
                    }
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
