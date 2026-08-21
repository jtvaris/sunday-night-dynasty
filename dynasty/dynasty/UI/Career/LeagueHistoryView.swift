import SwiftUI
import SwiftData

/// R32 — League History & Hall of Fame.
///
/// Three sections driven entirely by persisted data:
/// - **Season History**: one row per completed season (champion, the user's
///   record, playoff/title badges, MVP). Written by `WeekAdvancer` during the
///   `.superBowl` phase, capped at the last 20 seasons.
/// - **Franchise Archives** (TODO §5.2): any club's season-by-season record,
///   finish, roster strength and staff, from `TeamSeasonArchive` — the league
///   book seen from one building instead of from the commissioner's office.
/// - **Hall of Fame**: retired legends inducted by `PlayerRetirementEngine`
///   each offseason, newest class first.
struct LeagueHistoryView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here.
    @Query(sort: \Team.abbreviation) private var teamsUnscoped: [Team]
    private var teams: [Team] { teamsUnscoped.filter { $0.careerID == career.id } }

    /// Which franchise the archive section is showing. Defaults to the user's.
    @State private var archiveTeamID: UUID?
    @State private var archives: [TeamSeasonArchive] = []
    @State private var franchiseArc: LeagueNarrativeEngine.FranchiseArc?

    private var summaries: [SeasonSummary] { career.seasonSummaries }
    private var inductees: [HallOfFameEntry] { career.hallOfFame }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                careerTotalsCard
                draftReportLink

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    SectionHeaderText(title: "Season History")
                    if summaries.isEmpty {
                        emptyCard(
                            icon: "calendar",
                            text: "No completed seasons yet. Finish a season and the champion, your record, and the MVP are recorded here."
                        )
                    } else {
                        VStack(spacing: DSSpacing.xs) {
                            ForEach(summaries) { summary in
                                seasonRow(summary)
                            }
                        }
                    }
                }

                franchiseArchiveSection

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    SectionHeaderText(title: "Hall of Fame")
                    if inductees.isEmpty {
                        emptyCard(
                            icon: "building.columns.fill",
                            // The game's Hall is its own institution: no real
                            // shrine and no real city, so the copy says "the
                            // Hall", matching the section header above it.
                            text: "No inductees yet. Retiring legends — elite careers or sustained greatness — earn a bust in the Hall."
                        )
                    } else {
                        VStack(spacing: DSSpacing.xs) {
                            ForEach(inductees) { entry in
                                hofRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("League History")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadArchives() }
        .onChange(of: archiveTeamID) { _, _ in reloadSelectedFranchise() }
    }

    // MARK: - Franchise Archives (TODO §5.2)

    private var franchiseArchiveSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderText(title: "Franchise Archives")
                Spacer(minLength: DSSpacing.sm)
                if !teams.isEmpty {
                    Picker("Franchise", selection: $archiveTeamID) {
                        ForEach(teams) { team in
                            Text(team.fullName).tag(Optional(team.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.accentGold)
                }
            }

            if archives.isEmpty {
                emptyCard(
                    icon: "books.vertical.fill",
                    text: "No archived seasons for this club yet. Each completed season files a record, a finish, a roster rating and the staff that ran it."
                )
            } else {
                if let franchiseArc {
                    franchiseArcCard(franchiseArc)
                }
                VStack(spacing: DSSpacing.xs) {
                    ForEach(archives) { archive in
                        archiveRow(archive)
                    }
                }
            }
        }
    }

    /// The multi-season storyline the same engine puts in the news feed —
    /// shown here so the row list has a thesis above it rather than being a
    /// wall of records the reader has to summarise themselves.
    private func franchiseArcCard(_ arc: LeagueNarrativeEngine.FranchiseArc) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: arcIcon(arc.kind))
                .font(.title3)
                .foregroundStyle(arcColor(arc.sentiment))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(arc.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(arc.body)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func archiveRow(_ archive: TeamSeasonArchive) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DSSpacing.sm) {
                Text(String(archive.season))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 52, alignment: .leading)

                Text(archive.recordText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 56, alignment: .leading)

                Text("\(ordinalRank(archive.divisionRank)) \(archive.conferenceRaw) \(archive.divisionRaw)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.xs)

                if archive.rosterCount > 0 {
                    VStack(spacing: 1) {
                        Text(String(format: "%.0f", archive.avgOverall))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(Int(archive.avgOverall.rounded())))
                        Text("OVR")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                badge(archive.playoffResult.shortLabel, color: resultColor(archive.playoffResult))
            }

            // Staff + point differential: who ran it, and how it actually went.
            Text(staffLine(archive))
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)

            ForEach(Array(archive.notableEvents.enumerated()), id: \.offset) { _, event in
                Text("• \(event)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func staffLine(_ archive: TeamSeasonArchive) -> String {
        let differential = archive.pointDifferential
        let sign = differential > 0 ? "+" : ""
        return "HC \(archive.headCoachName) · OC \(archive.offensiveCoordinatorName)"
            + " · DC \(archive.defensiveCoordinatorName) · \(sign)\(differential) pt diff"
    }

    private func ordinalRank(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "—"
        }
    }

    private func resultColor(_ result: PlayoffResult) -> Color {
        switch result {
        case .champion:  return .accentGold
        case .runnerUp:  return .accentBlue
        case .conference, .divisional, .wildCard: return .success
        case .missed:    return .textTertiary
        }
    }

    private func arcIcon(_ kind: LeagueNarrativeEngine.FranchiseArc.Kind) -> String {
        switch kind {
        case .dynasty:    return "crown.fill"
        case .contender:  return "target"
        case .collapse:   return "arrow.down.right.circle.fill"
        case .drought:    return "hourglass"
        case .turnaround: return "arrow.up.right.circle.fill"
        }
    }

    private func arcColor(_ sentiment: NewsSentiment) -> Color {
        switch sentiment {
        case .positive: return .accentGold
        case .negative: return .danger
        case .neutral:  return .accentBlue
        }
    }

    /// Fills the archive in for any finished season that predates the rollover
    /// hook, then loads the selected franchise. Idempotent and a no-op once the
    /// archive is current, so opening this screen repeatedly costs one count
    /// query per season on the books.
    private func loadArchives() {
        let written = TeamSeasonArchiveBuilder.backfill(career: career, modelContext: modelContext)
        // Saved explicitly rather than left to autosave: the next read is the
        // fetch three lines down, and an unsaved insert would render an empty
        // archive on the very screen that just built it.
        if written > 0 { try? modelContext.save() }
        if archiveTeamID == nil {
            archiveTeamID = career.teamID ?? teams.first?.id
        }
        reloadSelectedFranchise()
    }

    private func reloadSelectedFranchise() {
        guard let teamID = archiveTeamID else {
            archives = []
            franchiseArc = nil
            return
        }
        archives = TeamSeasonArchiveBuilder.archives(
            careerID: career.id,
            teamID: teamID,
            modelContext: modelContext
        )
        franchiseArc = LeagueNarrativeEngine.franchiseArcs(archives: archives).first
    }

    // MARK: - Draft Report Card link

    /// #40 — entry point into the hindsight Draft Report Card. Placed here so
    /// the History screen (reachable from both the postseason and offseason
    /// quick-action bars) is a home for looking back at past draft classes.
    private var draftReportLink: some View {
        NavigationLink(value: CareerShellView.ShellDestination.draftReportCard) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "checklist")
                    .font(.title3)
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft Report Card")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Hindsight grades for every past draft class")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(DSSpacing.sm)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Career Totals

    private var careerTotalsCard: some View {
        HStack(spacing: DSSpacing.md) {
            totalStat(value: "\(career.totalWins)-\(career.totalLosses)", label: "Career Record")
            totalStat(value: "\(career.playoffAppearances)", label: "Playoff Berths")
            totalStat(value: "\(career.championships)", label: "Titles")
            totalStat(value: "\(inductees.count)", label: "HOF Inductees")
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func totalStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(label.uppercased())
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Season Row

    private func seasonRow(_ summary: SeasonSummary) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(String(summary.season))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentGold)
                    Text(summary.championTeamName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                if let mvp = summary.mvpName {
                    Text("MVP: \(mvp)\(summary.mvpTeamAbbr.map { " (\($0))" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.userRecordText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if summary.userWonChampionship {
                    badge("CHAMPIONS", color: .accentGold)
                } else if summary.userMadePlayoffs {
                    badge("PLAYOFFS", color: .accentBlue)
                } else {
                    badge("MISSED", color: .textTertiary)
                }
            }
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    // MARK: - HOF Row

    private func hofRow(_ entry: HallOfFameEntry) -> some View {
        HStack(spacing: DSSpacing.sm) {
            // The legend's portrait in a gold ring — the induction row is the
            // one place a retired player is still a person rather than a stat
            // line. Faces snapshotted at induction; a legend inducted before
            // faces existed has no image and never can, so the fallback is the
            // initials rather than one more identical silhouette in a column of
            // them.
            PersonFaceView(
                faceID: entry.faceID,
                size: .small,
                ringColor: .accentGold,
                accessibilityName: entry.playerName,
                placeholder: .monogram(
                    initials: PersonFaceView.initials(fromFullName: entry.playerName),
                    seed: entry.id
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if entry.wasUserTeamPlayer {
                        badge("YOUR LEGEND", color: .success)
                    }
                }
                Text("\(entry.positionRaw) • \(entry.seasonsPlayed) seasons • retired \(String(entry.inductionSeason)) (\(entry.retiredFromTeamName))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                if let production = careerProduction(entry) {
                    Text(production)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.accentGold.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(spacing: 1) {
                Text("\(entry.peakOverall)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.forRating(entry.peakOverall))
                Text("PEAK")
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    /// What the legend actually did on the field, in the same categories the
    /// career stat table shows for his position (`CareerStatColumns`) so the
    /// bust and the player page never disagree about what matters for a QB.
    ///
    /// Three tiers, because the entries are snapshots taken at induction and
    /// older classes were inducted before career totals were persisted (#21):
    /// the full line when it exists, the pre-phrased résumé when only that was
    /// stored, and nothing at all for a pre-stats class — which renders exactly
    /// as it did before, rather than as a row of confident zeros.
    private func careerProduction(_ entry: HallOfFameEntry) -> String? {
        guard let line = entry.careerStatLine, !line.isEmpty else {
            return entry.careerResume
        }

        var parts: [String]
        switch Position(rawValue: entry.positionRaw) {
        case .QB:
            parts = ["\(line.passYards) pass yd", "\(line.passTDs) TD", "\(line.passInts) INT"]
        case .RB, .FB:
            parts = ["\(line.rushYards) rush yd", "\(line.rushTDs) TD", "\(line.receptions) rec"]
        case .WR, .TE:
            parts = ["\(line.receptions) rec", "\(line.recYards) yd", "\(line.recTDs) TD"]
        case .LT, .LG, .C, .RG, .RT:
            // A lineman's career has no counting stats — snaps are the whole
            // honest record, and a Hall of Fame line of zeros would be a lie.
            parts = line.snapsPlayed > 0 ? ["\(line.snapsPlayed) snaps"] : []
        case .DE, .DT:
            parts = ["\(line.tackles) tkl", String(format: "%.1f sacks", line.sacks)]
        case .OLB, .MLB:
            parts = ["\(line.tackles) tkl", String(format: "%.1f sacks", line.sacks), "\(line.defInts) INT"]
        case .CB, .FS, .SS:
            parts = ["\(line.tackles) tkl", "\(line.defInts) INT", "\(line.passesDefended) PD"]
        case .K:
            parts = ["\(line.fieldGoalsMade)/\(line.fieldGoalsAttempted) FG"]
        case .P:
            parts = ["\(line.punts) punts", String(format: "%.1f avg", line.puntAverage)]
        case nil:
            // Position unreadable (a raw value from a future build): fall back
            // to the sentence rather than guessing at categories.
            return entry.careerResume
        }

        // A games count on its own is not a résumé — a lineman whose snaps were
        // never recorded reads better as the phrased sentence.
        guard !parts.isEmpty else { return entry.careerResume }
        if let games = entry.careerGamesPlayed, games > 0 {
            parts.append("\(games) G")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Bits

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DSType.Size.micro, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }

    private func emptyCard(icon: String, text: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.title3))
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }
}
