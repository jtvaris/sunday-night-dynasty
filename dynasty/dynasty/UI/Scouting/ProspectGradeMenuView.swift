import SwiftUI

// MARK: - Context Menu for User Grade & Star

/// Reusable context menu content for setting the GM's personal grade and star on a prospect.
struct ProspectGradeContextMenu: View {
    let prospectID: UUID
    @ObservedObject private var store = UserProspectGradeStore.shared

    var body: some View {
        // Star toggle
        Button {
            store.toggleStar(for: prospectID)
        } label: {
            Label(
                store.isStarred(prospectID) ? "Unstar" : "Star",
                systemImage: store.isStarred(prospectID) ? "star.slash" : "star.fill"
            )
        }

        // Grade submenu
        Menu {
            ForEach(UserGrade.allCases) { grade in
                Button {
                    store.setGrade(grade, for: prospectID)
                } label: {
                    HStack {
                        Text(grade.rawValue)
                        if store.grade(for: prospectID) == grade {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Clear Grade") {
                store.setGrade(nil, for: prospectID)
            }
        } label: {
            Label("Set My Grade", systemImage: "star.square")
        }
    }
}

// MARK: - Star Toggle Button (first column in prospect rows)

/// Tappable star button for starring/unstarring a prospect.
struct ProspectStarButton: View {
    let prospectID: UUID
    @ObservedObject private var store = UserProspectGradeStore.shared

    var body: some View {
        Button {
            store.toggleStar(for: prospectID)
        } label: {
            Image(systemName: store.isStarred(prospectID) ? "star.fill" : "star")
                .font(.system(size: 14))
                .foregroundStyle(store.isStarred(prospectID) ? Color.accentGold : Color.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Dual Grade Display (Own / Scout)

/// Shows dual grade display: "Own / Scout" format. If no user grade, shows scout grade only.
struct DualGradeDisplay: View {
    let prospectID: UUID
    let scoutGradeText: String
    let scoutGradeColor: Color
    @ObservedObject private var store = UserProspectGradeStore.shared

    var body: some View {
        if let userGrade = store.grade(for: prospectID) {
            HStack(spacing: 2) {
                Text(userGrade.letterGrade)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.success)
                Text("/")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(scoutGradeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentGold)
            }
        } else {
            Text(scoutGradeText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(scoutGradeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - User Grade Badge (inline display)

/// Small capsule badge showing the GM's personal grade and/or star next to a prospect name.
struct UserGradeBadge: View {
    let prospectID: UUID
    @ObservedObject private var store = UserProspectGradeStore.shared

    var body: some View {
        HStack(spacing: 3) {
            if let grade = store.grade(for: prospectID) {
                Text("My: \(grade.shortLabel)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(grade.color, in: Capsule())
            }
        }
    }
}

// MARK: - Info Tooltip Button (reusable explainer popover)

/// A small "(i)" button that opens an explainer popover. Use next to column headers
/// or inline with rating displays to explain notation like `87 (79)` (scout vs true).
///
/// Optional `showLetterGradeKey` adds the A/B/C/D/F tier color legend.
struct InfoTooltipButton: View {
    let text: String
    var showLetterGradeKey: Bool = false
    var size: CGFloat = 11
    var tint: Color = .accentBlue

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More info")
        .popover(isPresented: $showing, attachmentAnchor: .point(.center), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if showLetterGradeKey {
                    Divider().overlay(Color.surfaceBorder)
                    Text("Grade tiers")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .textCase(.uppercase)
                    LetterGradeLegend()
                }
            }
            .padding(14)
            .frame(maxWidth: 280)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Color legend for letter grades A-F. Matches `gradeColor(_:)` palette used in
/// ProspectListView / BigBoardView (success / accentGold / warning / danger).
struct LetterGradeLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            legendCell("A", color: .success)
            legendCell("B", color: .accentGold)
            legendCell("C", color: .warning)
            legendCell("D", color: .danger)
            legendCell("F", color: .danger)
        }
    }

    private func legendCell(_ letter: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: RoundedRectangle(cornerRadius: 4))
            Text(tierLabel(letter))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func tierLabel(_ letter: String) -> String {
        switch letter {
        case "A": return "Elite"
        case "B": return "Quality"
        case "C": return "Avg"
        case "D": return "Below"
        case "F": return "Poor"
        default:  return ""
        }
    }
}
