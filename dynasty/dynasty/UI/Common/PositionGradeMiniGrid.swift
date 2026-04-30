// PositionGradeMiniGrid.swift
//
// Reusable compact A-F position-group grade grid pattern for at-a-glance
// roster comparison. Originated from Roster Evaluation's "Position Group
// Grades" grid, which is one of the strongest at-a-glance UX patterns in
// the app.
//
// Recommended replication sites (off-limits to this agent in current
// session, but use this component when other agents touch them):
//   - Team Selection compare sheet (per-position grades)
//   - Standings: per-team position-grade snapshot row
//   - News view "Power Rankings" row when implemented
//   - Trade view: opponent roster strength preview
//   - Free Agency targets: needs-vs-grade overlay
//
// This component intentionally does not depend on any specific roster /
// team type. Callers compute the [PositionGroupGrade] entries (using
// PositionGradeCalculator) and pass them in. Single-responsibility: render
// the compact grid.

import SwiftUI

/// One row in the mini grid: a position group plus its starter / depth grade.
struct PositionGroupGradeEntry: Identifiable, Hashable {
    let id: String
    let label: String          // e.g. "QB", "OL", "DL", "LB", "DB"
    let starterGrade: String   // letter grade ("A", "B+", ...)
    let depthGrade: String     // letter grade
    /// Optional: when true, highlights this row as "weakest" (red tint).
    var isWeakest: Bool = false

    init(id: String? = nil,
         label: String,
         starterGrade: String,
         depthGrade: String,
         isWeakest: Bool = false) {
        self.id = id ?? label
        self.label = label
        self.starterGrade = starterGrade
        self.depthGrade = depthGrade
        self.isWeakest = isWeakest
    }
}

/// A compact two-column "S: A / D: B+" mini grid suitable for a comparison
/// sheet, standings row, or any list cell where space is tight but the user
/// needs to read multiple position grades at a glance.
struct PositionGradeMiniGrid: View {

    enum Style {
        /// Two-column layout (e.g. compare sheet, standings row).
        case twoColumn
        /// Single-column compact layout (e.g. trade preview, news row).
        case singleColumn
        /// Horizontal scrolling pills (e.g. tight news cell).
        case horizontalPills
    }

    let entries: [PositionGroupGradeEntry]
    var style: Style = .twoColumn
    var showHeader: Bool = false
    var headerText: String = "Position Grades"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                Text(headerText)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            switch style {
            case .twoColumn:
                twoColumnLayout
            case .singleColumn:
                singleColumnLayout
            case .horizontalPills:
                pillsLayout
            }
        }
    }

    // MARK: - Layouts

    private var twoColumnLayout: some View {
        let halfCount = (entries.count + 1) / 2
        let leftCol = Array(entries.prefix(halfCount))
        let rightCol = Array(entries.dropFirst(halfCount))

        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ForEach(leftCol) { row($0) }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                ForEach(rightCol) { row($0) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var singleColumnLayout: some View {
        VStack(spacing: 4) {
            ForEach(entries) { row($0) }
        }
    }

    private var pillsLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(entries) { entry in
                    pill(entry)
                }
            }
        }
    }

    // MARK: - Row variants

    private func row(_ entry: PositionGroupGradeEntry) -> some View {
        HStack(spacing: 6) {
            Text(entry.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, alignment: .leading)

            HStack(spacing: 2) {
                Text("S:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(entry.starterGrade)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(entry.starterGrade))

                Text("/")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)

                Text("D:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(entry.depthGrade)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(entry.depthGrade))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(entry.isWeakest ? Color.danger.opacity(0.10) : Color.clear)
        )
    }

    private func pill(_ entry: PositionGroupGradeEntry) -> some View {
        VStack(spacing: 2) {
            Text(entry.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            HStack(spacing: 2) {
                Text(entry.starterGrade)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(entry.starterGrade))
                Text("/")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                Text(entry.depthGrade)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(entry.depthGrade))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            entry.isWeakest ? Color.danger.opacity(0.40)
                                            : Color.textTertiary.opacity(0.20)
                        )
                )
        )
    }
}

#if DEBUG
#Preview("Two Column") {
    PositionGradeMiniGrid(
        entries: [
            .init(label: "QB", starterGrade: "A",  depthGrade: "C"),
            .init(label: "RB", starterGrade: "B+", depthGrade: "B"),
            .init(label: "WR", starterGrade: "B",  depthGrade: "C+"),
            .init(label: "OL", starterGrade: "B-", depthGrade: "C"),
            .init(label: "DL", starterGrade: "C",  depthGrade: "D",  isWeakest: true),
            .init(label: "LB", starterGrade: "B",  depthGrade: "C-"),
            .init(label: "DB", starterGrade: "B+", depthGrade: "C"),
        ],
        showHeader: true
    )
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Pills") {
    PositionGradeMiniGrid(
        entries: [
            .init(label: "QB", starterGrade: "A",  depthGrade: "C"),
            .init(label: "RB", starterGrade: "B+", depthGrade: "B"),
            .init(label: "WR", starterGrade: "B",  depthGrade: "C+"),
            .init(label: "DL", starterGrade: "C",  depthGrade: "D", isWeakest: true),
        ],
        style: .horizontalPills
    )
    .padding()
    .background(Color.backgroundPrimary)
}
#endif
