import SwiftUI

// MARK: - DSEmptyState
//
// UI_REDESIGN_VISION §2.7. One variant per density, always the same four beats:
//
//     icon  →  title  →  what would fill this  →  the action that fills it
//
// The model is the Big Board's own empty state (icon + title + a message that
// changes with WHY the list is empty + two CTAs), because it is the only one in
// the app that answers the third beat honestly: "you have no scouts on staff, so
// nobody is filing reports" is a different problem from "nobody has filed on
// this class yet", and they lead to different buttons.
//
// `Common/EmptyStateView.swift` predates this and is used by one of the ten
// list/detail screens. It stays for now — it is not this wave's file — but it
// has no density story, no second action and no cost→unlock line, so new call
// sites come here. The two are not meant to coexist forever.
//
// Density (P3) decides how much room the state is allowed to take, not what it
// says:
//
//   glance  a rail or a hub card — one line and a link, no halo
//   scan    a list that is empty — the full hero, up to two actions
//   study   a detail surface — the hero with room to breathe
//
// The buttons clear the 44 pt target floor (§2.12) at every density, including
// `glance`, where the visible control is small but its box is not.

struct DSEmptyState: View {

    /// One thing the user can press to make the emptiness go away. `isPrimary`
    /// gets the one gold fill; everything else is a secondary. Never two golds —
    /// P5 allows exactly one per screen, and an empty list IS the screen.
    struct Action {
        var title: String
        var systemImage: String?
        var isPrimary: Bool
        var handler: () -> Void

        init(
            title: String,
            systemImage: String? = nil,
            isPrimary: Bool = false,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isPrimary = isPrimary
            self.handler = handler
        }
    }

    var density: DSListDensity = .scan
    let icon: String
    let title: String
    /// Beat three: what would fill this. Not "No data" — the CONDITION that is
    /// missing, in the user's own vocabulary.
    var message: String? = nil
    var actions: [Action] = []

    var body: some View {
        switch density {
        case .glance: glanceBody
        case .scan:   heroBody(maxWidth: 380, iconSize: 44, halo: 76)
        case .study:  heroBody(maxWidth: 460, iconSize: 52, halo: 88)
        }
    }

    // MARK: Glance — a rail, a hub card, a panel with three numbers in it

    private var glanceBody: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DSType.text(13, .semibold))
                    .foregroundStyle(Color.textPrimary)
                if let message {
                    Text(message)
                        .font(DSType.text(12, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DSSpacing.xs)
            if let action = actions.first {
                button(action, compact: true)
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    // MARK: Scan / Study — the hero

    private func heroBody(maxWidth: CGFloat, iconSize: CGFloat, halo: CGFloat) -> some View {
        VStack(spacing: DSSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.backgroundTertiary)
                    .frame(width: halo, height: halo)
                Circle()
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    .frame(width: halo, height: halo)
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: DSSpacing.xxs + 2) {
                Text(title)
                    .font(DSType.text(17, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(DSType.text(14, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: maxWidth)

            if !actions.isEmpty {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        button(action, compact: false)
                    }
                }
                .padding(.top, DSSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
    }

    // MARK: Buttons

    private func button(_ action: Action, compact: Bool) -> some View {
        Button(action: action.handler) {
            Group {
                if let systemImage = action.systemImage, !compact {
                    Label(action.title, systemImage: systemImage)
                } else {
                    Text(action.title)
                }
            }
            .font(DSType.text(14, .semibold))
            .lineLimit(1)
            .foregroundStyle(action.isPrimary ? Color.backgroundPlate : Color.textPrimary)
            .padding(.horizontal, compact ? 12 : 18)
            // 44 pt in both axes, measured — §2.12 has no exceptions, and
            // iteration 2 of the vision shipped ~28 of them.
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(action.isPrimary ? Color.accentGold : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(
                        action.isPrimary ? Color.clear : Color.surfaceBorder,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Scan") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        DSEmptyState(
            density: .scan,
            icon: "list.star",
            title: "Big Board Is Empty",
            message: "You have no scouts on staff, so nobody is filing reports. Hire a scout, then order film study to build your board.",
            actions: [
                .init(title: "Hire Scouts", systemImage: "person.badge.plus", isPrimary: true) {},
                .init(title: "Combine Numbers", systemImage: "figure.run") {},
            ]
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Glance") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        DSEmptyState(
            density: .glance,
            icon: "tray",
            title: "No tasks this week",
            message: "Advance the week to see what the building needs.",
            actions: [.init(title: "Advance") {}]
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
