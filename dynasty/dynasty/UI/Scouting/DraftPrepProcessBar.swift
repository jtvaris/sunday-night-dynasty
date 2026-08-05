import SwiftUI

// MARK: - Stage cell model
//
// The bar is a dumb renderer. Everything it draws — state, counters, the reason
// a locked stage is locked — is computed once by the hub off
// `DraftPrepProgress` and handed down as a value, so the bar cannot disagree
// with the screen underneath it and a body re-evaluation never re-walks a
// 350-man draft class.

/// One stage of the pre-draft process, as the process bar draws it.
///
/// Built straight off a ``DraftPrepProgress/Stage`` — the counter string, the
/// meter fraction and the lock sentence are all that struct's, so the bar and
/// the required-task chain can never print different numbers for the same work.
struct DraftPrepStageCell: Identifiable, Equatable {

    /// Where the club stands relative to this stage.
    ///
    /// Four states, not two: the old hub HID everything ahead of the current
    /// step, so a user parked on stage 1 was looking at a six-tab screen with no
    /// evidence that pro days, workouts or visits existed at all. A locked stage
    /// is drawn, greyed, with the sentence that unlocks it.
    enum State: Equatable {
        /// Behind the club. Its screen opens read-only.
        case done
        /// Where the club is standing. Its screen is the working surface.
        case current
        /// Ahead of the club but already reachable — `DraftPrepProgress.reach`
        /// opens the next room the moment the current stage is satisfied, so
        /// this is the common state, not an edge case.
        case open
        /// Ahead of the club and shut, by the pipeline or by the calendar.
        case locked
    }

    let step: DraftPrepStep
    let state: State
    /// "30/60 interviews", or "Done" / "Not read" for the stages that are a read
    /// rather than a spend. Straight off `DraftPrepProgress.Stage.counter`.
    let counterText: String
    /// 0…1 fill for the cell's hairline meter.
    let fraction: Double
    /// One clause saying what opens this stage. Empty unless it is shut.
    let lockReason: String

    var id: String { step.rawValue }

    /// Screen-reader sentence: state, name, progress, and the unlock clause.
    var accessibilityText: String {
        var parts = ["Stage \(step.order + 1), \(step.displayName)"]
        switch state {
        case .done:    parts.append("complete")
        case .current: parts.append("current stage")
        case .open:    parts.append("open")
        case .locked:  parts.append("locked")
        }
        parts.append(counterText)
        if !lockReason.isEmpty { parts.append(lockReason) }
        return parts.joined(separator: ", ")
    }

    init(step: DraftPrepStep, state: State, stage: DraftPrepProgress.Stage) {
        self.step = step
        self.state = state
        self.counterText = stage.counter
        self.fraction = stage.fraction
        self.lockReason = stage.lockReason ?? ""
    }
}

// MARK: - Process bar

/// The scouting hub's primary navigation: the pre-draft calendar as a strip of
/// stage cells, in order, each carrying its own state and its own count of work.
///
/// This replaces the flat eleven-tab picker. The picker was a list of places,
/// which is the wrong shape for a process — it said nothing about order, nothing
/// about what was finished, and it *hid* every stage the club had not reached,
/// so the two most common failure reports against the shipped wizard ("pro days
/// were completely unavailable", "film study could not be assigned") were both a
/// user looking at a screen that had silently deleted the thing he was looking
/// for. Here every stage is always on screen, in calendar order, and a stage the
/// club cannot work yet says so in words.
struct DraftPrepProcessBar: View {
    let cells: [DraftPrepStageCell]
    /// The stage whose screen is currently showing — not necessarily the stage
    /// the club is standing in: a done stage opens read-only.
    let selected: DraftPrepStep?
    var onSelect: (DraftPrepStep) -> Void

    private let cellWidth: CGFloat = 92

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        if index > 0 { connector(before: cell) }
                        cellView(cell)
                            .id(cell.step)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: selected) { _, _ in scroll(proxy, animated: true) }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
        )
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        // Follow the SELECTED stage, falling back to the current one. Without
        // this the bar opens parked on stage 1 and a club six stages in has to
        // hunt for itself.
        let target = selected ?? cells.first(where: { $0.state == .current })?.step
        guard let target else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: - Connector

    /// The rail between two cells: gold behind work already done, hairline ahead
    /// of it. It is what makes the strip read as a pipeline rather than as a row
    /// of buttons.
    private func connector(before cell: DraftPrepStageCell) -> some View {
        Rectangle()
            .fill(cell.state == .done || cell.state == .current ? Color.accentGold : Color.surfaceBorder)
            .frame(width: 10, height: 1.5)
            .accessibilityHidden(true)
    }

    // MARK: - Cell

    private func cellView(_ cell: DraftPrepStageCell) -> some View {
        let isSelected = selected == cell.step
        return Button {
            onSelect(cell.step)
        } label: {
            VStack(spacing: 3) {
                marker(cell, isSelected: isSelected)

                Text(cell.step.displayName)
                    .font(.system(size: DSType.Size.micro, weight: isSelected ? .heavy : .semibold))
                    .foregroundStyle(nameColor(cell, isSelected: isSelected))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 24, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)

                counterLine(cell)
                meter(cell)
            }
            .frame(width: cellWidth)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(isSelected ? Color.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .strokeBorder(
                        isSelected ? Color.accentGold.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The numbered puck: a check when the stage is finished, a lock when it is
    /// ahead, the stage number otherwise.
    private func marker(_ cell: DraftPrepStageCell, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(markerFill(cell))
                .frame(width: 20, height: 20)
            Circle()
                .strokeBorder(
                    cell.state == .current ? Color.accentGold
                        : cell.state == .open ? Color.accentGold.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
                .frame(width: 24, height: 24)
            switch cell.state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
            case .current:
                Text("\(cell.step.order + 1)")
                    .font(.system(size: DSType.Size.micro, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.backgroundPrimary)
            case .open:
                Text("\(cell.step.order + 1)")
                    .font(.system(size: DSType.Size.micro, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            case .locked:
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 24)
    }

    private func markerFill(_ cell: DraftPrepStageCell) -> Color {
        switch cell.state {
        case .done:    return Color.success
        case .current: return Color.accentGold
        // Outlined, not filled: the room is open, nobody is standing in it yet.
        case .open:    return Color.backgroundTertiary
        case .locked:  return Color.backgroundTertiary
        }
    }

    private func nameColor(_ cell: DraftPrepStageCell, isSelected: Bool) -> Color {
        switch cell.state {
        case .current: return .accentGold
        case .open:    return .textPrimary
        case .done:    return isSelected ? .textPrimary : .textSecondary
        case .locked:  return .textTertiaryReadable
        }
    }

    private func counterLine(_ cell: DraftPrepStageCell) -> some View {
        // The counter is the whole point of the bar: the user asked to always
        // see "how much is done per stage", and a chevron between two tab names
        // never said that. The string is `DraftPrepProgress`'s, so the required
        // task in the left bar reads the same numbers.
        Text(cell.counterText)
            .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
            .foregroundStyle(counterColor(cell))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func counterColor(_ cell: DraftPrepStageCell) -> Color {
        switch cell.state {
        case .locked:  return .textTertiaryReadable
        case .done:    return cell.fraction > 0 ? .success : .textTertiaryReadable
        case .current: return .textPrimary
        case .open:    return .textSecondary
        }
    }

    private func meter(_ cell: DraftPrepStageCell) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.backgroundTertiary)
                Capsule()
                    .fill(cell.state == .done ? Color.success : Color.accentGold)
                    .frame(width: geo.size.width * cell.fraction)
            }
        }
        .frame(width: cellWidth - 24, height: 2.5)
        .accessibilityHidden(true)
    }
}

// MARK: - Reference tab row

/// The four surfaces that are NOT part of the pipeline — the board, the mock,
/// the draft order, the department, next year's class. They were mixed into the
/// same eleven-tab picker as the stages, which is what made the strip unreadable
/// as a process: a permanent reference screen sat between two dated stages.
struct ScoutingReferenceTabRow: View {
    let tabs: [ScoutingTab]
    let selected: ScoutingTab
    var onSelect: (ScoutingTab) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    let isSelected = selected == tab
                    Button {
                        onSelect(tab)
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .font(.system(size: DSType.Size.caption, weight: isSelected ? .heavy : .semibold))
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isSelected ? Color.accentBlue : Color.backgroundTertiary)
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.clear : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
            }
        )
    }
}
