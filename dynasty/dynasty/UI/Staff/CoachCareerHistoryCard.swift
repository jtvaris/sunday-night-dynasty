import SwiftUI
import SwiftData

/// The card on the coach profile that finally shows a real career: every
/// completed season, the club, the seat, the record and the rings.
///
/// ## What it is allowed to say
///
/// Everything here comes off ``CoachSeasonHistory`` rows, one per season, each
/// written at a season rollover from that season's `TeamSeasonArchive`. The
/// totals are ``CoachCareerRecord/total(_:)`` — plain sums over those rows.
/// Nothing is derived from age, years of experience or a hash of the coach's
/// id, which is what the EXPERIENCE card on the hire screen has to do and says
/// it does.
///
/// The one thing the copy has to be careful about is whose record it is. A
/// club goes 12-5; a defensive-backs coach does not. So the summary calls it
/// **club record in his seats**, the explainer names the franchise archive it
/// came from, and the head-coach line is broken out separately because that is
/// the only seat where "his record" is the ordinary football usage.
///
/// ## Why the rows are loaded rather than `@Query`-ed
///
/// The table holds one row per employed coach per season — roughly five hundred
/// a year — so a store-wide `@Query` filtered in memory would pull a decade of
/// the whole league's coaching history onto a screen that needs one man's. The
/// fetch here goes through `CoachSeasonHistoryBuilder.history`, whose predicate
/// is on the indexed `careerID` plus `coachID`.
struct CoachCareerHistoryCard: View {

    let coach: Coach

    @Environment(\.modelContext) private var modelContext

    @State private var seasons: [CoachSeasonHistory] = []
    @State private var didLoad = false

    /// Every completed season on the books, newest first.
    private var record: CoachCareerRecord? { CoachCareerRecord.total(seasons) }

    /// The same totals over the head-coach seasons alone. `nil` when he has
    /// never held the chair, in which case the line is not drawn at all.
    private var headCoachRecord: CoachCareerRecord? {
        CoachCareerRecord.total(seasons.filter { $0.role == .headCoach })
    }

    /// Club abbreviations in the order he served them, oldest first, each once.
    private var clubTrail: [String] {
        var seen: Set<UUID> = []
        var trail: [String] = []
        for row in seasons.sorted(by: { $0.season < $1.season }) where !seen.contains(row.teamID) {
            seen.insert(row.teamID)
            trail.append(row.teamAbbr)
        }
        return trail
    }

    var body: some View {
        DSDetailCard(
            "Career History",
            icon: "book.closed.fill",
            explainer: explainer
        ) {
            if let record {
                summary(record)
                Divider().overlay(Color.surfaceBorder)
                seasonTable
            } else {
                DSDetailNote(text: emptyText, icon: "clock.badge.questionmark")
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            reload()
        }
    }

    // MARK: - Copy

    private var explainer: String {
        record == nil
            ? "Every season this coach has completed, once the league has finished one with him in a seat."
            : "Every season he has completed. The **record is his club's**, taken from the same franchise archive League History reads — a position coach did not go 12-5, his employer did."
    }

    private var emptyText: String {
        "No completed seasons on the books yet. A coach's book opens at the first season rollover after he takes a seat; seasons before that cannot be reconstructed, because a coach row only ever remembered his current job."
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ record: CoachCareerRecord) -> some View {
        DSDetailRow(
            "Seasons",
            record.seasons == 1
                ? "1 (\(record.firstSeason))"
                : "\(record.seasons) (\(record.firstSeason)–\(record.lastSeason))"
        )

        DSDetailRow(
            "Clubs",
            clubTrail.isEmpty ? "\(record.clubs)" : "\(record.clubs) · \(clubTrail.joined(separator: " → "))"
        )

        DSDetailRow(label: "Club Record") {
            HStack(spacing: DSSpacing.xs) {
                Text(record.recordText)
                    .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text(record.winPercentageText)
                    .font(.system(size: DSType.Size.footnote, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
        }
        DSDetailNote(
            text: "\(record.games) games in his seats, across \(record.seasons) season\(record.seasons == 1 ? "" : "s"). Ties count half.",
            icon: "sum"
        )

        if let headCoachRecord {
            DSDetailRow(label: "As Head Coach") {
                HStack(spacing: DSSpacing.xs) {
                    Text(headCoachRecord.recordText)
                        .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text(headCoachRecord.winPercentageText)
                        .font(.system(size: DSType.Size.footnote, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
            }
            DSDetailNote(
                text: "\(headCoachRecord.seasons) season\(headCoachRecord.seasons == 1 ? "" : "s") in the chair — the seat where the record is genuinely his.",
                icon: "person.crop.square.filled.and.at.rectangle"
            )
        }

        DSDetailRow(label: "Titles") {
            Text("\(record.titles)")
                .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(record.titles > 0 ? Color.accentGold : Color.textSecondary)
        }

        DSDetailRow(label: "Playoff Seasons") {
            Text("\(record.playoffSeasons) of \(record.seasons)")
                .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(record.playoffSeasons > 0 ? Color.success : Color.textSecondary)
        }
    }

    // MARK: - Season table

    private var seasonTable: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            header
            ForEach(seasons) { row in
                seasonRow(row)
            }
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.xs) {
            Text("YEAR")
                .frame(width: 40, alignment: .leading)
            Text("CLUB")
                .frame(width: 44, alignment: .leading)
            Text("SEAT")
                .frame(width: 36, alignment: .leading)
            Text("REC")
                .frame(width: 52, alignment: .leading)
            Spacer(minLength: 0)
            Text("FINISH")
        }
        .font(.system(size: DSType.Size.micro, weight: .heavy))
        .tracking(1)
        .foregroundStyle(Color.textTertiary)
        .accessibilityHidden(true)
    }

    private func seasonRow(_ row: CoachSeasonHistory) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(String(row.season))
                .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.accentGold)
                .frame(width: 40, alignment: .leading)

            Text(row.teamAbbr)
                .font(.system(size: DSType.Size.footnote, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)

            Text(row.role?.abbreviation ?? "—")
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, alignment: .leading)
                .lineLimit(1)

            Text(row.recordText)
                .font(.system(size: DSType.Size.footnote, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .frame(width: 52, alignment: .leading)

            Spacer(minLength: DSSpacing.xxs)

            Text(row.playoffResult.shortLabel)
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .foregroundStyle(finishColor(row.playoffResult))
                .padding(.horizontal, DSSpacing.xxs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(finishColor(row.playoffResult).opacity(0.15))
                )
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenRow(row))
    }

    /// The same five-way mapping League History paints its franchise rows with,
    /// so one season reads the same colour on both screens.
    private func finishColor(_ result: PlayoffResult) -> Color {
        switch result {
        case .champion:  return .accentGold
        case .runnerUp:  return .accentBlue
        case .conference, .divisional, .wildCard: return .success
        case .missed:    return .textTertiary
        }
    }

    private func spokenRow(_ row: CoachSeasonHistory) -> String {
        let seat = row.role?.displayName ?? row.roleRaw
        return "\(row.season), \(row.teamName), \(seat), \(row.recordText), \(row.playoffResult.label)"
    }

    // MARK: - Load

    private func reload() {
        guard let careerID = coach.careerID else {
            seasons = []
            return
        }
        seasons = CoachSeasonHistoryBuilder.history(
            careerID: careerID,
            coachID: coach.id,
            modelContext: modelContext
        )
    }
}
