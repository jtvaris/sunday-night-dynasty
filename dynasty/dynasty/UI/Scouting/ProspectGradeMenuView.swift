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
