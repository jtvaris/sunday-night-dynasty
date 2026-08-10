import SwiftUI

// MARK: - Play Clock Setting

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
        case .off:     return String(localized: "Off")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // Audio
    @AppStorage("soundEnabled") private var soundEnabled = true
    /// Master game-sounds volume (0…1): every match SFX and the crowd bed.
    /// Read by `AudioDirector` on every cue, so changes apply mid-game.
    @AppStorage("soundVolume") private var soundVolume = AudioSettings.soundVolumeDefault
    /// Soundtrack on/off, independent of the match SFX above. Read by
    /// `MusicDirector` on every track change and on the settings notification.
    @AppStorage("musicEnabled") private var musicEnabled = true
    /// Music level (0…1). Defaults lower than the game-sounds slider because
    /// the score is background by design and the crowd is the star of a match.
    @AppStorage("musicVolume") private var musicVolume = AudioSettings.musicVolumeDefault

    // Gameplay
    @AppStorage("playClockSetting") private var playClockRaw: String = PlayClockSetting.ten.rawValue
    /// Live-game quarter reports (end of Q1/Q3 player situation card).
    /// Read by `CoachedGameView` via the shared "quarterReportsEnabled" key.
    @AppStorage("quarterReportsEnabled") private var quarterReportsEnabled = true

    // Tutorial replay flag — picked up by MainMenuView to re-present the tutorial sheet.
    @AppStorage("pendingTutorialReplay") private var pendingTutorialReplay = false

    // Local UI state
    @State private var showResetConfirm = false
    @State private var showResetSuccess = false
    @State private var showChangelog = false
    /// R37: confirmation that first-run tips were re-armed.
    @State private var showTipsResetSuccess = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                Form {
                    audioSection
                    gameplaySection
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
            .alert("Tips reset", isPresented: $showTipsResetSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("One-time hints will show again: the dashboard tour, the first-snap walkthrough, and the in-game hint banners.")
            }
            .sheet(isPresented: $showChangelog) {
                ChangelogSheet()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var audioSection: some View {
        Section {
            // "Game Sounds", not "Sound": the row below it is a *separate*
            // level from Music, and a toggle called "Sound" reads like a
            // master mute for the whole app — which it is not.
            Toggle(isOn: $soundEnabled) {
                Label("Game Sounds", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            volumeRow(title: "Game Sounds Volume",
                      value: $soundVolume,
                      enabled: soundEnabled)

            Toggle(isOn: $musicEnabled) {
                Label("Music", systemImage: "music.note")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)

            volumeRow(title: "Music Volume",
                      value: $musicVolume,
                      enabled: musicEnabled)
        } header: {
            sectionHeader("Audio")
        } footer: {
            Text("Two independent levels. Game Sounds covers the live-game stadium — crowd, whistles, hits, and horns. Music is the menu and front-office score; it steps aside completely during a coached game, so the two are never loud at the same time. Both respect the mute switch and never interrupt your own music.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// A named volume control: title, live percentage, and the slider.
    ///
    /// The percentage is not decoration. A bare slider between two speaker
    /// glyphs gives no way to tell 30 % from 40 %, to describe a setting, or
    /// to put it back where it was after experimenting — and these two rows
    /// look identical to each other, so the title is what makes it obvious
    /// which one is being dragged.
    private func volumeRow(title: LocalizedStringKey,
                           value: Binding<Double>,
                           enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary)
            }
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary)
                Slider(value: value, in: 0...1, step: 0.05)
                    .tint(Color.accentGold)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .disabled(!enabled)
        .listRowBackground(Color.backgroundSecondary)
    }

    private var gameplaySection: some View {
        Section {
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

            Toggle(isOn: $quarterReportsEnabled) {
                Label("Quarter Reports", systemImage: "chart.bar.doc.horizontal")
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentGold)
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Gameplay")
        } footer: {
            Text("Play Clock limits live-game decision time — when it runs out, the QB or defense checks into a simple base call (never a penalty). Quarter Reports pause a live game after Q1 and Q3 with a player situation card.")
                .foregroundStyle(Color.textTertiary)
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

            // R37: re-arm every one-time coach mark and hint banner.
            Button {
                FirstRunTip.resetAll()
                showTipsResetSuccess = true
            } label: {
                HStack {
                    Label("Reset Tips", systemImage: "lightbulb.fill")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            sectionHeader("Tutorial")
        } footer: {
            Text("Replay Tutorial walks through the major systems from the main menu. Reset Tips shows the one-time hints (dashboard tour, first-snap walkthrough, in-game banners) again.")
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

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
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
        soundVolume = AudioSettings.soundVolumeDefault
        musicEnabled = true
        musicVolume = AudioSettings.musicVolumeDefault
        playClockRaw = PlayClockSetting.ten.rawValue
        quarterReportsEnabled = true
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
                                        .font(.system(size: 5))  // ds-lint:allow(font) decorative list bullet glyph, not text
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
