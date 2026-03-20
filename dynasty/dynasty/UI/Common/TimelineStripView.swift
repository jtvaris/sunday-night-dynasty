import SwiftUI

/// A compact horizontal scrollable strip showing the NFL calendar year.
/// The current phase is highlighted in gold with a "NOW" badge; past phases
/// show a gray checkmark; future phases are empty circles.
struct TimelineStripView: View {

    let currentPhase: SeasonPhase
    let currentWeek: Int

    // Ordered list of all phases in calendar sequence
    private static let orderedPhases: [SeasonPhase] = [
        .coachingChanges,
        .reviewRoster,
        .combine,
        .freeAgency,
        .proDays,
        .draft,
        .otas,
        .trainingCamp,
        .preseason,
        .rosterCuts,
        .regularSeason,
        .tradeDeadline,
        .playoffs,
        .superBowl
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(Self.orderedPhases.enumerated()), id: \.offset) { index, phase in
                        HStack(spacing: 0) {
                            // Connecting line before first item (half-width)
                            if index == 0 {
                                Color.clear.frame(width: 16, height: 1)
                            } else {
                                connectorLine(beforePhase: phase)
                            }

                            phaseNode(phase: phase)
                                .id(phase)

                            // Trailing half-line after last item
                            if index == Self.orderedPhases.count - 1 {
                                Color.clear.frame(width: 16, height: 1)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .onAppear {
                    // Scroll to current phase without animation on initial appear
                    proxy.scrollTo(currentPhase, anchor: .center)
                }
                .onChange(of: currentPhase) { _, newPhase in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(newPhase, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 64)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Phase State

    private enum PhaseState {
        case past, current, future
    }

    private func state(for phase: SeasonPhase) -> PhaseState {
        guard let currentIndex = Self.orderedPhases.firstIndex(of: currentPhase),
              let phaseIndex = Self.orderedPhases.firstIndex(of: phase) else {
            return .future
        }
        if phaseIndex < currentIndex { return .past }
        if phaseIndex == currentIndex { return .current }
        return .future
    }

    // MARK: - Node

    private func phaseNode(phase: SeasonPhase) -> some View {
        let phaseState = state(for: phase)
        let isCurrent = phaseState == .current

        return VStack(spacing: 3) {
            ZStack {
                // Circle background
                Circle()
                    .fill(circleBackground(for: phaseState))
                    .frame(width: 22, height: 22)

                // Circle border (future phases only)
                if phaseState == .future {
                    Circle()
                        .strokeBorder(Color.textSecondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }

                // Icon inside circle
                Group {
                    switch phaseState {
                    case .past:
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    case .current:
                        Image(systemName: phaseIcon(phase))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.backgroundPrimary)
                    case .future:
                        Image(systemName: phaseIcon(phase))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                    }
                }
            }
            .overlay(alignment: .top) {
                if isCurrent {
                    Text("NOW")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.accentGold)
                        )
                        .offset(y: -10)
                }
            }

            // Phase label
            Text(phaseLabel(phase))
                .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.accentGold : (phaseState == .past ? Color.textSecondary.opacity(0.6) : Color.textSecondary.opacity(0.5)))
                .lineLimit(1)
                .fixedSize()

            // Date range
            Text(phaseDateRange(phase))
                .font(.system(size: 8))
                .foregroundStyle(isCurrent ? Color.accentGold.opacity(0.8) : Color.textSecondary.opacity(0.35))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 68)
    }

    // MARK: - Connector Line

    private func connectorLine(beforePhase phase: SeasonPhase) -> some View {
        let phaseState = state(for: phase)
        let isPast = phaseState == .past
        let isCurrent = phaseState == .current

        return Rectangle()
            .fill(isPast || isCurrent ? Color.accentGold.opacity(0.5) : Color.textSecondary.opacity(0.2))
            .frame(width: 16, height: 1.5)
            .padding(.bottom, 22) // Align with circle center (approx)
    }

    // MARK: - Helpers

    private func circleBackground(for state: PhaseState) -> Color {
        switch state {
        case .past:    return Color.textSecondary.opacity(0.35)
        case .current: return Color.accentGold
        case .future:  return Color.clear
        }
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        switch phase {
        case .coachingChanges: return "Coaching"
        case .combine:         return "Combine"
        case .freeAgency:      return "Free Agency"
        case .proDays:         return "Pro Days"
        case .reviewRoster:    return "Review Roster"
        case .draft:           return "Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Cuts"
        case .regularSeason:   return "Regular"
        case .tradeDeadline:   return "Trade Line"
        case .playoffs:        return "Playoffs"
        case .superBowl:       return "Super Bowl"
        case .proBowl:         return "Pro Bowl"
        }
    }

    private func phaseDateRange(_ phase: SeasonPhase) -> String {
        switch phase {
        case .coachingChanges: return "Feb"
        case .combine:         return "Feb–Mar"
        case .freeAgency:      return "Mar"
        case .proDays:         return "Apr"
        case .reviewRoster:    return "Mar–Apr"
        case .draft:           return "Apr"
        case .otas:            return "May"
        case .trainingCamp:    return "Jul–Aug"
        case .preseason:       return "Aug"
        case .rosterCuts:      return "Aug"
        case .regularSeason:   return "Sep–Jan"
        case .tradeDeadline:   return "Oct"
        case .playoffs:        return "Jan"
        case .superBowl:       return "Feb"
        case .proBowl:         return "Feb"
        }
    }

    private func phaseIcon(_ phase: SeasonPhase) -> String {
        switch phase {
        case .coachingChanges: return "person.badge.key.fill"
        case .combine:         return "stopwatch.fill"
        case .freeAgency:      return "signature"
        case .proDays:         return "figure.run"
        case .reviewRoster:    return "chart.bar.doc.horizontal"
        case .draft:           return "list.clipboard.fill"
        case .otas:            return "figure.run"
        case .trainingCamp:    return "tent.fill"
        case .preseason:       return "football.fill"
        case .rosterCuts:      return "scissors"
        case .regularSeason:   return "sportscourt.fill"
        case .tradeDeadline:   return "arrow.left.arrow.right"
        case .playoffs:        return "trophy.fill"
        case .superBowl:       return "star.fill"
        case .proBowl:         return "star.circle.fill"
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TimelineStripView(currentPhase: .regularSeason, currentWeek: 8)
        TimelineStripView(currentPhase: .draft, currentWeek: 0)
        TimelineStripView(currentPhase: .coachingChanges, currentWeek: 0)
    }
    .background(Color.backgroundPrimary)
}
