import SwiftUI
import SwiftData

/// #40 — Draft Report Card. A HINDSIGHT review of the user team's past draft
/// classes: how each pick actually panned out **relative to the round he was
/// taken in**. A 7th-round starter is an A+; a 1st-round bench-warmer is a bust.
///
/// Purely analytical — it reads live `Player` rows + `PlayerSeasonHistory` and
/// runs them through `DraftGradeEngine`. It never mutates simulation state and
/// persists nothing.
///
/// The class grade *matures*: a rookie class is graded leniently and flagged
/// PRELIMINARY (players haven't had time to develop or earn starts yet), so the
/// letter here is expected to move as those players play more seasons.
struct DraftClassReportView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    // Loaded once on appear (see `loadIfNeeded`).
    @State private var loaded = false
    @State private var seasons: [Int] = []
    @State private var classesBySeason: [Int: DraftGradeEngine.ClassGrade] = [:]
    @State private var playersByID: [UUID: Player] = [:]
    @State private var selectedSeason: Int?

    private var selectedClass: DraftGradeEngine.ClassGrade? {
        guard let s = selectedSeason else { return nil }
        return classesBySeason[s]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if seasons.isEmpty {
                    emptyState
                } else {
                    seasonSelector
                    if let cls = selectedClass {
                        classGradeHeader(cls)
                        highlightCards(cls)
                        picksList(cls)
                        maturityFootnote(cls)
                    } else {
                        noPicksCard
                    }
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("Draft Report Card")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Load

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let teamID = career.teamID else { return }

        let fetch = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.draftedByTeamID == teamID }
        )
        let drafted = (try? modelContext.fetch(fetch)) ?? []
        playersByID = Dictionary(drafted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let seasonSet = Set(drafted.compactMap { $0.draftSeason })
        seasons = seasonSet.sorted(by: >)

        for s in seasons {
            classesBySeason[s] = DraftGradeEngine.classGrade(
                season: s, teamID: teamID, modelContext: modelContext
            )
        }
        selectedSeason = seasons.first
    }

    // MARK: - Season selector

    private var seasonSelector: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Draft Class")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(seasons, id: \.self) { season in
                        seasonChip(season)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func seasonChip(_ season: Int) -> some View {
        let isSelected = season == selectedSeason
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedSeason = season }
        } label: {
            Text(String(season))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Class grade header

    private func classGradeHeader(_ cls: DraftGradeEngine.ClassGrade) -> some View {
        let provisional = cls.picks.allSatisfy(\.isProvisional)
        return HStack(alignment: .center, spacing: DSSpacing.md) {
            gradeBadge(cls.letter, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text("Class of \(String(cls.season))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(cls.picks.count) \(cls.picks.count == 1 ? "pick" : "picks") · overall class grade")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if provisional {
                    Label("Preliminary — class still developing", systemImage: "hourglass")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .cardBackground()
    }

    // MARK: - Best pick / biggest miss

    @ViewBuilder
    private func highlightCards(_ cls: DraftGradeEngine.ClassGrade) -> some View {
        let best = cls.bestPickID.flatMap { id in cls.picks.first { $0.playerID == id } }
        let miss = cls.biggestMissID.flatMap { id in cls.picks.first { $0.playerID == id } }
        // Only surface a "miss" card when it's meaningfully different from the best pick.
        let showMiss = miss != nil && miss?.playerID != best?.playerID

        HStack(alignment: .top, spacing: DSSpacing.sm) {
            if let best {
                highlightCard(
                    title: "Best Pick", icon: "star.fill",
                    tint: .success, grade: best
                )
            }
            if showMiss, let miss {
                highlightCard(
                    title: "Biggest Miss", icon: "arrow.down.right",
                    tint: .danger, grade: miss
                )
            }
        }
    }

    private func highlightCard(
        title: String, icon: String, tint: Color, grade: DraftGradeEngine.PlayerGrade
    ) -> some View {
        let player = playersByID[grade.playerID]
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(player?.fullName ?? "Pick")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let player {
                    Text(player.position.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text(pickLabel(round: grade.round, pick: grade.pickNumber))
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Text(grade.summary)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Picks list

    private func picksList(_ cls: DraftGradeEngine.ClassGrade) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Every Pick")
            VStack(spacing: DSSpacing.xs) {
                ForEach(cls.picks) { grade in
                    pickRow(grade)
                }
            }
        }
    }

    private func pickRow(_ grade: DraftGradeEngine.PlayerGrade) -> some View {
        let player = playersByID[grade.playerID]
        return HStack(spacing: DSSpacing.sm) {
            // Pick provenance
            VStack(alignment: .leading, spacing: 2) {
                Text("R\(grade.round)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold)
                Text("#\(grade.pickNumber)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 38, alignment: .leading)

            // Name + position + development
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player?.fullName ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let player {
                        Text(player.position.rawValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.backgroundTertiary)
                            )
                    }
                }
                HStack(spacing: 10) {
                    statPill(label: "OVR", value: "\(grade.peakOVR)")
                    statPill(label: "GS", value: "\(grade.careerStarts)")
                    statPill(label: "GP", value: "\(grade.careerGames)")
                    if grade.ovrDevelopment > 0 {
                        statPill(label: "+DEV", value: "+\(grade.ovrDevelopment)")
                    }
                }
            }

            Spacer(minLength: 0)

            // Verdict chip
            verdictChip(grade)

            // Letter grade
            gradeBadge(grade.letter, size: 40)
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private func verdictChip(_ grade: DraftGradeEngine.PlayerGrade) -> some View {
        if grade.isProvisional {
            chip(text: "TBD", tint: .textTertiary)
        } else if grade.isBust {
            chip(text: "BUST", tint: .danger)
        } else if grade.isHit {
            chip(text: "HIT", tint: .success)
        }
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )
    }

    // MARK: - Grade badge

    private func gradeBadge(_ letter: String, size: CGFloat) -> some View {
        let tint = gradeColor(letter)
        return Text(letter)
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(tint.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                    )
            )
    }

    private func gradeColor(_ letter: String) -> Color {
        switch letter.first {
        case "A": return .success
        case "B": return .accentGold
        case "C": return .warning
        default:  return .danger
        }
    }

    private func pickLabel(round: Int, pick: Int) -> String {
        "Round \(round) · pick #\(pick)"
    }

    // MARK: - Footnote

    private func maturityFootnote(_ cls: DraftGradeEngine.ClassGrade) -> some View {
        let age = career.currentSeason - cls.season
        let text: String
        if age <= 1 {
            text = "First-year classes are graded leniently and marked preliminary — starts and development take seasons to accrue, so these letters will move as the class matures."
        } else {
            text = "Grades are relative to draft round: a late-round starter outgrades an early-round backup. They keep shifting until every pick's career plays out."
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DSSpacing.xs)
    }

    // MARK: - Empty / edge states

    private var emptyState: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.textTertiary)
            Text("No draft classes yet")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Once you make picks on Draft Day, each class shows up here with a hindsight report card — best pick, biggest miss, and a letter grade for every selection that matures as your players develop.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.lg)
        .cardBackground()
    }

    private var noPicksCard: some View {
        Text("No graded picks in this class.")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.md)
            .cardBackground()
    }
}
