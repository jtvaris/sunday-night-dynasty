import SwiftUI
import SwiftData

// MARK: - EventAlertView

struct EventAlertView: View {

    let event: GameEvent
    let career: Career
    let onRespond: (EventOption) -> Void
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var selectedOption: EventOption?
    @State private var showConfirmation = false
    @State private var relatedPlayerName: String?
    @State private var relatedCoachName: String?
    @State private var navigateToPlayer = false
    @State private var relatedPlayer: Player?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    Divider()
                        .overlay(Color.surfaceBorder)
                        .padding(.vertical, 20)
                    optionsSection
                    Spacer(minLength: 32)
                }
                .padding(24)
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Dismiss") { onDismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .sheet(isPresented: $navigateToPlayer) {
            if let player = relatedPlayer {
                NavigationStack {
                    PlayerDetailView(player: player)
                }
            }
        }
        .task { loadRelatedNames() }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Event type badge
            Text(event.type.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(event.type.badgeColor))

            // Headline
            Text(event.headline)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Related person
            if let playerName = relatedPlayerName {
                relatedPersonRow(
                    icon: "person.fill",
                    label: "Player",
                    name: playerName,
                    showInfoLink: relatedPlayer != nil
                )
            } else if let coachName = relatedCoachName {
                relatedPersonRow(
                    icon: "whistle.fill",
                    label: "Coach",
                    name: coachName,
                    showInfoLink: false
                )
            }

            // Description
            Text(event.description)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
    }

    private func relatedPersonRow(icon: String, label: String, name: String, showInfoLink: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            if showInfoLink {
                Button {
                    navigateToPlayer = true
                } label: {
                    HStack(spacing: 4) {
                        Text("More Info")
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
        )
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How will you respond?")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            ForEach(event.options) { option in
                optionCard(option)
            }

            if let selected = selectedOption {
                confirmButton(for: selected)
            }
        }
    }

    private func optionCard(_ option: EventOption) -> some View {
        let isSelected = selectedOption?.id == option.id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedOption = option
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Label row
                HStack {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentGold)
                            .font(.system(size: 18))
                    }
                }

                // Description
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Effects row
                Divider().overlay(Color.surfaceBorder.opacity(0.6))
                effectsRow(option)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? Color.accentGold : Color.surfaceBorder,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func effectsRow(_ option: EventOption) -> some View {
        HStack(spacing: 12) {
            effectPill(label: "Morale",    value: option.moraleEffect)
            effectPill(label: "Locker Rm", value: option.lockerRoomEffect)
            effectPill(label: "Owner",     value: option.ownerEffect)
            effectPill(label: "Media",     value: option.mediaEffect)
        }
    }

    private func effectPill(label: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(effectText(value))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(effectColor(value))
        }
        .frame(maxWidth: .infinity)
    }

    private func effectText(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\(value)" }
        return "—"
    }

    private func effectColor(_ value: Int) -> Color {
        if value > 0 { return Color.success }
        if value < 0 { return Color.danger }
        return Color.textTertiary
    }

    private func confirmButton(for option: EventOption) -> some View {
        Button {
            onRespond(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                Text("Confirm: \(option.label)")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentGold)
                    .shadow(color: Color.accentGold.opacity(0.4), radius: 10, x: 0, y: 4)
            )
        }
        .padding(.top, 6)
    }

    // MARK: - Data

    private func loadRelatedNames() {
        if let playerID = event.playerID {
            let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerID })
            if let player = try? modelContext.fetch(descriptor).first {
                relatedPlayerName = "\(player.firstName) \(player.lastName)"
                relatedPlayer = player
            }
        }
        if let coachID = event.coachID {
            let descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.id == coachID })
            if let coach = try? modelContext.fetch(descriptor).first {
                relatedCoachName = coach.fullName
            }
        }
    }
}

// MARK: - EventType Display Helpers

extension EventType {
    var displayName: String {
        switch self {
        case .holdout:                return "Holdout"
        case .suspension:             return "Suspension"
        case .arrest:                 return "Conduct"
        case .socialMediaIncident:    return "Social Media"
        case .retirementSpeculation:  return "Retirement"
        case .podcastControversy:     return "Media"
        case .manOfTheYear:           return "Community"
        case .voluntaryWorkouts:      return "Team Culture"
        case .rookieImpresses:        return "Rookie Watch"
        case .coachConflict:          return "Coaching"
        case .coordinatorInterview:   return "Coaching"
        case .veteranReturn:          return "Veteran"
        case .injurySetback:          return "Injury"
        case .aheadOfSchedule:        return "Injury"
        case .freakInjury:            return "Injury"
        case .contractDispute:        return "Contract"
        case .tradeRequest:           return "Trade Request"
        case .teamChemistry:          return "Locker Room"
        }
    }

    var badgeColor: Color {
        switch self {
        case .holdout:                return Color.warning
        case .suspension:             return Color.danger
        case .arrest:                 return Color.danger
        case .socialMediaIncident:    return Color.danger.opacity(0.8)
        case .retirementSpeculation:  return Color.textSecondary
        case .podcastControversy:     return Color.accentBlue
        case .manOfTheYear:           return Color.success
        case .voluntaryWorkouts:      return Color.success.opacity(0.8)
        case .rookieImpresses:        return Color.accentBlue.opacity(0.8)
        case .coachConflict:          return Color(red: 0.9, green: 0.45, blue: 0.1)
        case .coordinatorInterview:   return Color(red: 0.9, green: 0.45, blue: 0.1)
        case .veteranReturn:          return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .injurySetback:          return Color.danger.opacity(0.8)
        case .aheadOfSchedule:        return Color.success
        case .freakInjury:            return Color.danger
        case .contractDispute:        return Color.warning
        case .tradeRequest:           return Color.accentGold
        case .teamChemistry:          return Color(red: 0.2, green: 0.6, blue: 0.6)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleOption1 = EventOption(
        label: "Support publicly",
        description: "Hold a press conference defending your player.",
        moraleEffect: 5,
        lockerRoomEffect: 3,
        ownerEffect: -2,
        mediaEffect: 2
    )
    let sampleOption2 = EventOption(
        label: "Suspend immediately",
        description: "Show the league you hold your players accountable.",
        moraleEffect: -4,
        lockerRoomEffect: -2,
        ownerEffect: 4,
        mediaEffect: 5
    )
    let sampleOption3 = EventOption(
        label: "No comment",
        description: "Stay silent and let the story blow over.",
        moraleEffect: 0,
        lockerRoomEffect: 0,
        ownerEffect: -1,
        mediaEffect: -3
    )
    let event = GameEvent(
        type: .arrest,
        headline: "Star receiver arrested after nightclub incident",
        description: "Your star wide receiver was involved in an altercation outside a downtown nightclub late Sunday night. TMZ is running the story and reporters are camped outside the facility. How you respond will define team culture.",
        playerID: nil,
        coachID: nil,
        teamID: UUID(),
        options: [sampleOption1, sampleOption2, sampleOption3],
        week: 6,
        season: 2026
    )
    NavigationStack {
        EventAlertView(
            event: event,
            career: Career(playerName: "Alex Reid", role: .gm, capMode: .simple),
            onRespond: { _ in },
            onDismiss: {}
        )
    }
    .modelContainer(for: [Career.self, Player.self, Coach.self], inMemory: true)
}
