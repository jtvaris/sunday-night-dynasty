import SwiftUI

// MARK: - Setting Enums

/// Simulation pacing — affects how long week advancement animations linger.
enum GameSpeed: String, CaseIterable, Identifiable {
    case fast, normal, slow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fast:   return "Fast"
        case .normal: return "Normal"
        case .slow:   return "Slow"
        }
    }
}

/// User-facing color scheme override.
enum ThemePreference: String, CaseIterable, Identifiable {
    case dark, auto, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark:   return "Dark"
        case .auto:   return "Auto"
        case .system: return "System"
        }
    }
}

/// Live-game decision clock: how long the coach gets to call a play before
/// the QB (offense) or the DC (defense) checks into a simple base call and
/// the snap goes off automatically. Never a delay-of-game penalty.
/// Read by `CoachedGameView` via the shared "playClockSetting" UserDefaults key.
enum PlayClockSetting: String, CaseIterable, Identifiable {
    case ten = "10"
    case fifteen = "15"
    case off = "off"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ten:     return "10 s"
        case .fifteen: return "15 s"
        case .off:     return "Off"
        }
    }
}

/// Difficulty tier — drives AI strength multipliers across systems.
enum Difficulty: String, CaseIterable, Identifiable {
    case easy, normal, hard, realistic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy:      return "Easy"
        case .normal:    return "Normal"
        case .hard:      return "Hard"
        case .realistic: return "Realistic"
        }
    }
    var subtitle: String {
        switch self {
        case .easy:      return "Forgiving CPU rivals"
        case .normal:    return "Balanced league"
        case .hard:      return "Sharper opponents"
        case .realistic: return "Unforgiving simulation"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // General
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    // Gameplay
    @AppStorage("gameSpeed") private var gameSpeedRaw: String = GameSpeed.normal.rawValue
    @AppStorage("difficulty") private var difficultyRaw: String = Difficulty.normal.rawValue
    @AppStorage("playClockSetting") private var playClockRaw: String = PlayClockSetting.ten.rawValue

    // Appearance
    @AppStorage("themePreference") private var themeRaw: String = ThemePreference.dark.rawValue

    // Notifications
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifyCapWarnings") private var notifyCapWarnings = true
    @AppStorage("notifyContractExpirations") private var notifyContractExpirations = true
    @AppStorage("notifyDraftPicks") private var notifyDraftPicks = true

    // Tutorial replay flag — picked up by MainMenuView to re-present the tutorial sheet.
    @AppStorage("pendingTutorialReplay") private var pendingTutorialReplay = false

    // Local UI state
    @State private var showResetConfirm = false
    @State private var showResetSuccess = false
    @State private var showChangelog = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    private var gameSpeed: GameSpeed {
        GameSpeed(rawValue: gameSpeedRaw) ?? .normal
    }

    private var difficulty: Difficulty {
        Difficulty(rawValue: difficultyRaw) ?? .normal
    }

    private var theme: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .dark
    }

    private var resolvedColorScheme: ColorScheme? {
        switch theme {
        case .dark:   return .dark
        case .auto:   return .dark   // app is dark-first; "Auto" follows app default
        case .system: return nil     // honor system
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                Form {
                    generalSection
                    gameplaySection
                    appearanceSection
                    notificationsSection
                    tutorialSection
                    dataSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentGold)
                }
            }
            .confirmationDialog(
                "Reset all save data?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Save Data", role: .destructive) {
                    performReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently clears every career, roster note, watchlist entry, and preference. This cannot be undone.")
            }
            .alert("Save data cleared", isPresented: $showResetSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All Dynasty data has been removed from this device.")
            }
            .sheet(isPresented: $showChangelog) {
                ChangelogSheet()
            }
        }
        .preferredColorScheme(resolvedColorScheme)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            Toggle(isOn: $soundEnabled) {
                Label("Sound", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            Toggle(isOn: $hapticsEnabled) {
                Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("General")
        }
    }

    private var gameplaySection: some View {
        Section {
            Picker(selection: $gameSpeedRaw) {
                ForEach(GameSpeed.allCases) { speed in
                    Text(speed.label).tag(speed.rawValue)
                }
            } label: {
                Label("Simulation Speed", systemImage: "hare.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            Picker(selection: $difficultyRaw) {
                ForEach(Difficulty.allCases) { level in
                    Text(level.label).tag(level.rawValue)
                }
            } label: {
                Label("Difficulty", systemImage: "flame.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            HStack {
                Spacer().frame(width: 28)
                Text(difficulty.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .listRowBackground(Color.backgroundSecondary)

            Picker(selection: $playClockRaw) {
                ForEach(PlayClockSetting.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            } label: {
                Label("Play Clock", systemImage: "timer")
                    .foregroundStyle(Color.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Gameplay")
        } footer: {
            Text("Difficulty affects AI roster construction, trade valuation, and free-agent competition. Play Clock limits live-game decision time — when it runs out, the QB or defense checks into a simple base call (never a penalty).")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $themeRaw) {
                ForEach(ThemePreference.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            } label: {
                Label("Theme", systemImage: "paintbrush.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Appearance")
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Enable Notifications", systemImage: "bell.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            Toggle(isOn: $notifyCapWarnings) {
                Label("Cap Warnings", systemImage: "dollarsign.circle.fill")
                    .foregroundStyle(notificationsEnabled ? Color.textPrimary : Color.textTertiary)
            }
            .tint(Color.accentGold)
            .disabled(!notificationsEnabled)
            .listRowBackground(Color.backgroundSecondary)

            Toggle(isOn: $notifyContractExpirations) {
                Label("Contract Expirations", systemImage: "doc.text.fill")
                    .foregroundStyle(notificationsEnabled ? Color.textPrimary : Color.textTertiary)
            }
            .tint(Color.accentGold)
            .disabled(!notificationsEnabled)
            .listRowBackground(Color.backgroundSecondary)

            Toggle(isOn: $notifyDraftPicks) {
                Label("Draft Picks", systemImage: "star.fill")
                    .foregroundStyle(notificationsEnabled ? Color.textPrimary : Color.textTertiary)
            }
            .tint(Color.accentGold)
            .disabled(!notificationsEnabled)
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Notifications")
        }
    }

    private var tutorialSection: some View {
        Section {
            Button {
                pendingTutorialReplay = true
                dismiss()
            } label: {
                HStack {
                    Label("Replay Tutorial", systemImage: "graduationcap.fill")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Tutorial")
        } footer: {
            Text("Walks through the major systems of the game from the main menu.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                HStack {
                    Label("Delete All Save Data", systemImage: "trash.fill")
                        .foregroundStyle(Color.danger)
                    Spacer()
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Data")
        } footer: {
            Text("Removes every career, roster note, watchlist entry, and preference from this device. This cannot be undone.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(appVersion)
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)

            HStack {
                Label("Developer", systemImage: "person.fill")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("JT Varis")
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)

            HStack {
                Label("Credits", systemImage: "heart.fill")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("Made with SwiftUI")
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)

            Button {
                showChangelog = true
            } label: {
                HStack {
                    Label("Changelog", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("About")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(Color.accentGold)
    }

    /// Wipes every key from the app's UserDefaults suite.
    private func performReset() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Re-seed defaults so the UI reflects fresh state immediately.
        soundEnabled = true
        hapticsEnabled = true
        gameSpeedRaw = GameSpeed.normal.rawValue
        difficultyRaw = Difficulty.normal.rawValue
        playClockRaw = PlayClockSetting.ten.rawValue
        themeRaw = ThemePreference.dark.rawValue
        notificationsEnabled = true
        notifyCapWarnings = true
        notifyContractExpirations = true
        notifyDraftPicks = true
        pendingTutorialReplay = false
        showResetSuccess = true
    }
}

// MARK: - Changelog Sheet

private struct ChangelogSheet: View {

    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let bullets: [String]
    }

    private let entries: [Entry] = [
        Entry(
            version: "Latest",
            date: "April 2026",
            bullets: [
                "Big Board fixes & ProspectDetailView redesign",
                "2026 salary cap update",
                "Scouting pipeline improvements"
            ]
        ),
        Entry(
            version: "Earlier",
            date: "Spring 2026",
            bullets: [
                "Coach candidate overhaul",
                "Combine, board, and interview improvements",
                "Contract negotiation chat-bubble UI"
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    ForEach(entries) { entry in
                        Section {
                            ForEach(entry.bullets, id: \.self) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(Color.accentGold)
                                        .padding(.top, 7)
                                    Text(line)
                                        .foregroundStyle(Color.textPrimary)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        } header: {
                            HStack {
                                Text(entry.version)
                                    .foregroundStyle(Color.accentGold)
                                Spacer()
                                Text(entry.date)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Changelog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
}
