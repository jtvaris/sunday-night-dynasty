import SwiftUI

// MARK: - HalftimeView

/// Full-screen halftime report shown between Q2 and Q3 of a live coached
/// game: first-half line score, total yards, the battles that defined the
/// half, and the coach's ONE second-half adjustment — a small edge that
/// ``LiveGameEngine`` applies to the player team's offensive plays after
/// the break.
struct HalftimeView: View {

    @ObservedObject var engine: LiveGameEngine
    let homeTeam: Team
    let awayTeam: Team
    let playerTeamIsHome: Bool
    /// Called with the chosen adjustment (`nil` = no change) when the coach
    /// taps "Continue to 2nd Half".
    let onContinue: (HalftimeAdjustment?) -> Void

    @State private var selection: HalftimeAdjustment? = nil

    /// Report = line score, battles, and the adjustment; Players = the same
    /// per-player situation panel the quarter reports use (shared component,
    /// so Q2's end never stacks two overlays).
    private enum Tab { case report, players }
    @State private var tab: Tab = .report

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("HALFTIME")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentGold, in: Capsule())

                    tabSwitcher

                    if tab == .report {
                        lineScoreGrid

                        totalYardsRow

                        keyBattles

                        adjustmentPicker
                    } else {
                        QuarterPlayersPanel(engine: engine)
                    }

                    Button {
                        onContinue(selection)
                    } label: {
                        Text("Continue to 2nd Half")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 13)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(30)
                .frame(maxWidth: 720)
                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
                )
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tabs

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            tabButton("REPORT", isOn: tab == .report) { tab = .report }
            tabButton("PLAYERS", isOn: tab == .players) { tab = .players }
        }
        .padding(3)
        .background(Color.backgroundTertiary, in: Capsule())
    }

    private func tabButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15), action)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .foregroundStyle(isOn ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isOn ? Color.accentGold : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Line score (Q1 / Q2 / total)

    private var lineScoreGrid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 8) {
            GridRow {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["Q1", "Q2"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44)
                }
                Text("T")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 48)
            }
            lineScoreRow(
                abbr: awayTeam.abbreviation,
                quarters: engine.awayQuarterScores,
                total: engine.awayScore,
                isPlayer: !playerTeamIsHome
            )
            lineScoreRow(
                abbr: homeTeam.abbreviation,
                quarters: engine.homeQuarterScores,
                total: engine.homeScore,
                isPlayer: playerTeamIsHome
            )
        }
        .padding(14)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func lineScoreRow(abbr: String, quarters: [Int], total: Int, isPlayer: Bool) -> some View {
        GridRow {
            Text(abbr)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<2, id: \.self) { index in
                Text("\(quarters.indices.contains(index) ? quarters[index] : 0)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44)
            }
            Text("\(total)")
                .font(.system(size: 16, weight: .black).monospacedDigit())
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
                .frame(width: 48)
        }
    }

    // MARK: - Total yards

    private var totalYardsRow: some View {
        let awayYards = engine.totalYards(forHome: false)
        let homeYards = engine.totalYards(forHome: true)
        return StatComparisonRow(
            label: "Total Yards",
            awayValue: "\(awayYards)",
            homeValue: "\(homeYards)",
            awayRaw: Double(awayYards),
            homeRaw: Double(homeYards)
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Key battles

    @ViewBuilder
    private var keyBattles: some View {
        let battles = engine.topFirstHalfMatchupEvents(limit: 3)
        if !battles.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle("BATTLES OF THE HALF", icon: "flame.fill")
                ForEach(battles) { event in
                    battleRow(event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func battleRow(_ event: PlayMatchups.Event) -> some View {
        let (icon, tint): (String, Color) = {
            switch event.kind {
            case .bust: return ("book.closed.fill", Color(red: 0.72, green: 0.55, blue: 0.95))
            case .star: return ("star.fill", .accentGold)
            default:    return ("figure.american.football", .accentBlue)
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(event.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Second-half adjustment

    private var adjustmentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("COACH'S ADJUSTMENT — 2ND HALF", icon: "slider.horizontal.3")
            Text("Pick one small edge for your offense after the break (optional).")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
            HStack(spacing: 10) {
                ForEach(HalftimeAdjustment.allCases) { option in
                    adjustmentCard(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adjustmentCard(_ option: HalftimeAdjustment) -> some View {
        let isSelected = selection == option
        return Button {
            withAnimation(.spring(duration: 0.15)) {
                selection = isSelected ? nil : option
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textSecondary)
                Text(option.rawValue)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
                Text(option.blurb)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentGold)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentGold.opacity(0.14) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text(text)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
        }
    }
}
