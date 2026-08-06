import SwiftUI
import SwiftData

// MARK: - Unified Mark Controls
//
// One mark system, three shapes: a menu (context menus and the row control),
// a chip (board rows and lists), and a full picker (the prospect card's
// verdict block). Everything writes through `CollegeProspect.setUserMark`, so
// the legacy flag and star mirrors stay in step wherever the user marks him.

/// Menu content for setting a prospect's mark tier. Drop into a `Menu` or a
/// `.contextMenu`.
struct ProspectMarkMenu: View {
    let prospect: CollegeProspect
    /// Called after a write so the caller can save the context / refresh a cache.
    var onChange: (() -> Void)? = nil
    /// Optional hook for "Edit Note…", shown only when supplied.
    var onEditNote: (() -> Void)? = nil

    var body: some View {
        ForEach(ProspectMarkTier.choices) { tier in
            Button {
                // Tapping the tier a prospect already has clears it, so the
                // same control both marks and unmarks.
                prospect.setUserMark(prospect.userMark == tier ? .none : tier)
                onChange?()
            } label: {
                Label(
                    prospect.userMark == tier ? "\(tier.label) \u{2713}" : tier.label,
                    systemImage: tier.icon
                )
            }
        }
        if prospect.isMarked {
            Divider()
            Button(role: .destructive) {
                prospect.setUserMark(.none)
                onChange?()
            } label: {
                Label("Clear Mark", systemImage: "xmark.circle")
            }
        }
        if let onEditNote {
            Divider()
            Button {
                onEditNote()
            } label: {
                Label(
                    prospect.userMarkNote.isEmpty ? "Add Note" : "Edit Note",
                    systemImage: "note.text"
                )
            }
        }
    }
}

/// The leading-column control on a board / list row: shows the current mark and
/// opens the mark menu. Replaces the old star button, which wrote a fourth
/// parallel opinion nothing else read.
struct ProspectMarkButton: View {
    let prospect: CollegeProspect
    var onChange: (() -> Void)? = nil
    var onEditNote: (() -> Void)? = nil

    var body: some View {
        Menu {
            ProspectMarkMenu(prospect: prospect, onChange: onChange, onEditNote: onEditNote)
        } label: {
            Image(systemName: prospect.isMarked ? prospect.userMark.icon : "circle.dashed")
                .font(.system(size: 15))
                .foregroundStyle(prospect.isMarked ? prospect.userMark.color : Color.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            prospect.isMarked
                ? "Mark: \(prospect.userMark.label). Change mark for \(prospect.fullName)"
                : "Unmarked. Set mark for \(prospect.fullName)"
        )
    }
}

/// Compact tier badge for a row. Renders nothing for an unmarked prospect, so
/// a board with no verdicts on it looks exactly as it did.
struct ProspectMarkChip: View {
    let mark: ProspectMarkTier
    var showsNote: Bool = false

    var body: some View {
        if mark != .none {
            HStack(spacing: 2) {
                Text(mark.shortLabel)
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                if showsNote {
                    Image(systemName: "note.text")
                        .font(.system(size: DSType.Size.micro))
                }
            }
            .foregroundStyle(Color.backgroundPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(mark.color, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Your mark: \(mark.label)")
        }
    }
}

/// Value-vs-my-grade chip: what the market thinks minus what you graded him.
/// Renders nothing when the user has not graded him, when the media has no
/// consensus slot for him, or when he is fully fogged.
struct ProspectValueChip: View {
    let read: ProspectFog.ValueRead?
    var compact: Bool = true

    var body: some View {
        if let read, read.isMeaningful {
            Text(compact ? read.chipText : read.label)
                .font(.system(size: compact ? 8 : 9, weight: .heavy).monospacedDigit())
                .foregroundStyle(read.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(
                    read.isValue
                        ? "Value: the market has him \(read.delta) picks later than your grade"
                        : "Reach: your grade is \(abs(read.delta)) picks ahead of the market"
                )
        } else {
            Text("\u{2014}")
                .font(.system(size: compact ? 8 : 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

/// The verdict block on the prospect card: four tiers, the current one filled,
/// plus the note the GM wrote next to it. This is the deep dive finally
/// recording an opinion instead of ending in a dead end.
struct ProspectMarkPicker: View {
    let prospect: CollegeProspect
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ProspectMarkTier.choices) { tier in
                    let isSelected = prospect.userMark == tier
                    Button {
                        prospect.setUserMark(isSelected ? .none : tier)
                        onChange?()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tier.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tier.label)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(isSelected ? Color.backgroundPrimary : tier.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(isSelected ? tier.color : Color.backgroundTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .strokeBorder(
                                    isSelected ? tier.color : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tier.label): \(tier.blurb)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            Text(prospect.isMarked ? prospect.userMark.blurb : "Tap a tier to put him on your board.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

// MARK: - Mark Note Sheet

/// The one-line verdict the GM writes beside the tier.
struct ProspectMarkNoteSheet: View {
    let prospectName: String
    @State private var noteText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(
        prospectName: String,
        initialNote: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prospectName = prospectName
        self._noteText = State(initialValue: initialNote)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(prospectName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("Why he is where he is on your board.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)

                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                    )

                Text("\(noteText.count)/200")
                    .font(.caption)
                    .foregroundStyle(noteText.count > 200 ? Color.danger : Color.textTertiary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Board Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(String(noteText.prefix(200))) }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Context Menu for Mark & Grade

/// Reusable context-menu content: the unified mark tier first (it is the
/// verdict), then the GM's own draft grade, then the work a surface can start
/// on him without leaving the list.
///
/// The star toggle that used to head this menu is gone — the mark replaced it,
/// and `setUserMark` keeps the star store written for whatever still reads it.
struct ProspectGradeContextMenu: View {
    let prospect: CollegeProspect
    var onChange: (() -> Void)? = nil
    var onEditNote: (() -> Void)? = nil
    /// Optional hook for "Conduct Interview", shown only when supplied.
    ///
    /// **The menu knows nothing about the interview economy on purpose.** An
    /// interview is rationed twice over — a 60-slot cycle allowance and a window
    /// that is combine week only — and each surface runs it through its own
    /// flow (the interview room batches a selection; a prospect card spends one
    /// slot on one man). A menu that tried to own the gate would need the
    /// career, the slot ledger and the phase, and would still have nowhere to
    /// put the result. So the caller decides whether the action exists at all:
    /// pass a closure when the surface can honestly run it, pass nothing and the
    /// item is not drawn (#116).
    var onInterview: (() -> Void)? = nil
    @ObservedObject private var store = UserProspectGradeStore.shared

    var body: some View {
        ProspectMarkMenu(prospect: prospect, onChange: onChange, onEditNote: onEditNote)

        Divider()

        // Grade submenu
        Menu {
            ForEach(UserGrade.allCases) { grade in
                Button {
                    store.setGrade(grade, for: prospect.id)
                    onChange?()
                } label: {
                    HStack {
                        Text(grade.rawValue)
                        if store.grade(for: prospect.id) == grade {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Clear Grade") {
                store.setGrade(nil, for: prospect.id)
                onChange?()
            }
        } label: {
            Label("Set My Grade", systemImage: "star.square")
        }

        // The work, under the opinions. Same icon the hub's Interviews tab
        // carries, so the long-press and the tab read as the same instrument.
        if let onInterview {
            Divider()
            Button(action: onInterview) {
                Label("Conduct Interview", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}

// MARK: - Dual Grade Display (Own / Scout)

/// Shows dual grade display: "Own / Scout" format. If no user grade, shows scout grade only.
/// Optionally renders a stock trajectory chevron (↗ rising / ↘ falling / ✦ new) next to the grade.
struct DualGradeDisplay: View {
    let prospectID: UUID
    let scoutGradeText: String
    let scoutGradeColor: Color
    /// Optional trajectory — when supplied, shows a small directional arrow.
    var trajectory: StockTrajectory? = nil
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
                trajectoryArrow
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("My grade \(userGrade.letterGrade), scout grade \(scoutGradeText)")
        } else {
            HStack(spacing: 2) {
                Text(scoutGradeText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(scoutGradeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                trajectoryArrow
            }
            .accessibilityLabel("Scout grade \(scoutGradeText)")
        }
    }

    @ViewBuilder
    private var trajectoryArrow: some View {
        if let traj = trajectory, traj == .rising || traj == .falling {
            Image(systemName: traj.icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(traj.color)
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
                    .font(.system(size: DSType.Size.micro, weight: .bold))
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

/// Color legend for letter grades A-F. Colors come straight from
/// `PositionGradeCalculator.gradeColorForLetter`, the single source every list
/// renders from (A green, B blue, C yellow, D/F red) — the legend used to claim
/// B → gold, which contradicted every grade on screen.
struct LetterGradeLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            legendCell("A")
            legendCell("B")
            legendCell("C")
            legendCell("D")
            legendCell("F")
        }
    }

    private func legendCell(_ letter: String) -> some View {
        legendCell(letter, color: PositionGradeCalculator.gradeColorForLetter(letter))
    }

    private func legendCell(_ letter: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            Text(tierLabel(letter))
                .font(.system(size: DSType.Size.micro, weight: .medium))
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
