import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                List {
                    // MARK: - General
                    Section {
                        Toggle(isOn: $soundEnabled) {
                            Label("Sound", systemImage: "speaker.wave.2.fill")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.accentGold)
                        .listRowBackground(Color.backgroundSecondary)

                        Toggle(isOn: $notificationsEnabled) {
                            Label("Notifications", systemImage: "bell.fill")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.accentGold)
                        .listRowBackground(Color.backgroundSecondary)
                    } header: {
                        Text("General")
                            .foregroundStyle(Color.accentGold)
                    }

                    // MARK: - About
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
                    } header: {
                        Text("About")
                            .foregroundStyle(Color.accentGold)
                    }
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
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
}
