import SwiftUI

// MARK: - Shared prospect-list controls
//
// ONE control strip, worn by every prospect table.
//
// The Big Board grew these controls first and nothing else inherited them. The
// position chips were hoisted into `ScoutingHubView` (one tap filters the board,
// the film screen and the combine table together), but the column-block picker
// stayed a `private var` on `BigBoardView` — so the combine table shipped as a
// single frozen column set, with no way to ask it "who have I not worked up" or
// "who have I not been in a room with". A user who learned the board's controls
// then found half of them missing one tab to the right.
//
// Everything here takes BINDINGS and owns no state. That is the load-bearing
// rule: the hub keeps THREE deliberately separate filter states — the shared
// position chips, the board's mark filter, and the board's own round / risk
// menu — and folding any two of them behind one control is exactly the bug the
// hub's chip hoist was written to fix. A shared control that owned the
// selection would re-merge them the moment a second list adopted it.

/// The position chip row: All / QB / RB / WR / TE / OL / DL / LB / DB.
///
/// Verbatim the hub's chip bar, extracted so a list that is NOT hosted under it
/// (a pro-day list, a workout list) can wear the same control instead of
/// inventing a fourth position filter.
struct ProspectPositionChips: View {
    @Binding var selection: ProspectPositionFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    let isSelected = selection == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Color.accentBlue : Color.backgroundTertiary,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.clear : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter == .all
                                        ? "Show all positions"
                                        : "Filter to \(filter.label)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
        )
    }
}

/// The column-block picker: Overview / Work-up / Physical / Mental / Position.
///
/// `modes` is a parameter because not every table can answer every question with
/// the same block — the combine's home block is its drills, the board's is the
/// overview — but the control, the order and the look are one thing everywhere.
struct ProspectModeChips: View {
    @Binding var mode: ProspectAttributeTab
    var modes: [ProspectAttributeTab] = ProspectAttributeTab.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modes) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(mode == tab ? Color.backgroundPrimary : Color.textSecondary)
                        .background(
                            mode == tab ? Color.accentBlue : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    mode == tab ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .accessibilityLabel("View mode: \(tab.label)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(Color.backgroundPrimary)
    }
}

/// The strip a prospect list pins above its column headers.
///
/// `showsPositionChips` is off by default because the three tables the scouting
/// hub hosts already sit under the hub's own chip bar, and two identical chip
/// rows stacked on one screen is a worse bug than the missing control was. A
/// list hosted anywhere else turns it on and passes the same binding.
struct ProspectListControls: View {
    @Binding var positionFilter: ProspectPositionFilter
    @Binding var mode: ProspectAttributeTab
    var modes: [ProspectAttributeTab] = ProspectAttributeTab.allCases
    var showsPositionChips: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if showsPositionChips {
                ProspectPositionChips(selection: $positionFilter)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
            if !modes.isEmpty {
                ProspectModeChips(mode: $mode, modes: modes)
            }
        }
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Shared table cells
//
// The cell shapes a prospect table's attribute blocks are built from. They
// were private helpers on `BigBoardRowView`; a second table rendering the
// same blocks means one definition or two that drift.
//
// There is deliberately NO revealed-integer cell here: a raw 0-99 attribute
// is generator truth no instrument ever discloses (the #110/#114 fog audit),
// so the shared vocabulary only speaks in fogged measurables and grade bands.

/// A scouted grade BAND over its column label — "B" when the department is
/// certain, "C+/A-" when it is not, "?" when nobody has filed on him.
struct ProspectGradeBandCell: View {
    let grade: GradeRange?
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            if let grade {
                Text(grade.displayText)
                    .font(.system(size: grade.isSingleGrade ? 10 : 8, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade.midGrade.rawValue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("?")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

/// A yes/no fact about the WORK, drawn dim rather than blank when it has not
/// been done — the hole is the thing the user is scanning for.
struct ProspectWorkTick: View {
    let done: Bool
    var tint: Color = .success

    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11))
            .foregroundStyle(done ? tint : Color.textTertiary.opacity(0.35))
            .accessibilityHidden(true)
    }
}

// `ProspectPositionSkills` used to live here as the per-position key table.
// It had drifted from the engine's writer (`SAc`/`DAc`/`TAK` vs the written
// `SAC`/`DAC`/`TKL`), so every table now reads the canonical
// `ProspectFog.positionSkillKeys(for:)` instead — one table, owned next to
// the disclosure logic it feeds.
