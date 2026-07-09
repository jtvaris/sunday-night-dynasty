import SwiftUI

/// R24 — Post-draft summary + Undrafted Free Agency stage.
///
/// Shown when the draft completes: left column recaps the user's draft class,
/// right column lists the best remaining undrafted prospects (ranked by the
/// user's scout grades — hidden OVR never shown). The user may sign up to
/// five UDFAs on cheap 1-2 year deals before releasing the pool to the
/// league; AI teams then round-robin the best of the rest.
struct DraftUDFAPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    private var userResults: [PickResult] {
        coordinator.allPickResults.filter { $0.isUserPick || $0.ownerOverride }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.surfaceBorder)
            HStack(spacing: 0) {
                recapColumn
                    .frame(maxWidth: 340)
                Divider().overlay(Color.surfaceBorder)
                udfaColumn
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DRAFT COMPLETE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.6)
                    .foregroundStyle(Color.accentGold)
                Text("Undrafted Free Agency — \(coordinator.draftYear)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            if !coordinator.udfaStageFinished {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Signed \(coordinator.signedUDFAProspectIDs.count)/\(coordinator.maxUDFASignings)")
                        .font(.callout.monospaced().weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("1-2 yr deals · ~$0.5-0.8M/yr")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Draft class recap

    private var recapColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                SectionHeaderText(title: "Your Draft Class")
                if userResults.isEmpty {
                    Text("No selections made this year.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                ForEach(userResults) { result in
                    HStack(spacing: DSSpacing.xs) {
                        Text("R\(result.round) · #\(result.pickNumber)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(result.playerName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text(result.position.rawValue)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Text(result.grade.rawValue)
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.backgroundTertiary)
                            .foregroundStyle(result.isGem ? Color.draftStealGold : Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(DSSpacing.xs)
                    .cardBackground()
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundSecondary.opacity(0.5))
    }

    // MARK: - UDFA pool

    private var udfaColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    SectionHeaderText(title: "Undrafted Free Agents")
                    Text("Ranked by your scouting grades. The best names go fast once the league opens the phones.")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(Array(coordinator.udfaPool.prefix(40)), id: \.id) { prospect in
                        udfaRow(prospect)
                    }
                    if coordinator.udfaPool.isEmpty {
                        Text("Every declared prospect found a home in the draft.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, DSSpacing.md)
                    }
                }
                .padding(DSSpacing.md)
            }
            Divider().overlay(Color.surfaceBorder)
            footer
        }
    }

    private func udfaRow(_ prospect: CollegeProspect) -> some View {
        let signed = coordinator.signedUDFAProspectIDs.contains(prospect.id)
        let need = coordinator.teamNeedScores[prospect.position] ?? 0
        let trend = prospect.stockTrajectory

        return HStack(spacing: DSSpacing.sm) {
            Text(prospect.overallGradeDisplay)
                .font(.caption.monospaced().weight(.heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 48, alignment: .leading)
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(need >= 0.5 ? Color.draftStealGold : Color.textSecondary)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if trend == .rising || trend == .falling {
                        Image(systemName: trend.icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(trend.color)
                    }
                    if need >= 0.5 {
                        Text("NEED")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.draftStealGold)
                    }
                }
                Text(prospect.college)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if signed {
                Label("Signed", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.success)
            } else if !coordinator.udfaStageFinished {
                Button {
                    coordinator.signUDFA(prospect)
                } label: {
                    Text("SIGN")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(canSignMore ? Color.accentGold : Color.backgroundTertiary)
                        .foregroundStyle(canSignMore ? Color.backgroundPrimary : Color.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                }
                .buttonStyle(.plain)
                .disabled(!canSignMore)
            }
        }
        .padding(DSSpacing.xs)
        .cardBackground()
    }

    private var canSignMore: Bool {
        coordinator.signedUDFAProspectIDs.count < coordinator.maxUDFASignings
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DSSpacing.md) {
            if coordinator.udfaStageFinished {
                Label(
                    coordinator.udfaAISummary ?? "UDFA market closed.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.success)
                Spacer()
                Text("Advance the week from the dashboard to head into OTAs.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Unsigned prospects go to the open market when you finish.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button {
                    coordinator.finishUDFASigning()
                } label: {
                    Label("Finish — league signs the rest", systemImage: "flag.checkered")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentGold)
            }
        }
        .padding(DSSpacing.md)
        .background(Color.backgroundSecondary)
    }
}
