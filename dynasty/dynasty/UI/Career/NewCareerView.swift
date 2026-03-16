import SwiftUI
import SwiftData

struct NewCareerView: View {

    @State private var playerName: String = ""
    @State private var selectedAvatarID: String = "coach_m1"
    @State private var selectedRole: CareerRole = .gm
    @State private var selectedCapMode: CapMode = .simple

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Form {
                // MARK: - Player Info
                Section {
                    TextField("Enter your name", text: $playerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .listRowBackground(Color.backgroundSecondary)
                } header: {
                    Text("Player Name")
                } footer: {
                    Text("This is how you'll be known around the league.")
                }

                // MARK: - Avatar Selection
                Section {
                    AvatarSelectionView(selectedAvatarID: $selectedAvatarID)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.backgroundSecondary)
                } header: {
                    Text("Your Look")
                } footer: {
                    if let avatar = CoachAvatars.avatar(for: selectedAvatarID) {
                        Text("\"\(avatar.name)\" — \(avatar.gender == .male ? "Male" : "Female") coach")
                    }
                }

                // MARK: - Role Selection
                Section {
                    Picker("Role", selection: $selectedRole) {
                        Text("General Manager").tag(CareerRole.gm)
                        Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.backgroundSecondary)
                } header: {
                    Text("Career Role")
                } footer: {
                    Group {
                        switch selectedRole {
                        case .gm:
                            Text("Focus on roster building, trades, the draft, and free agency. You'll hire a head coach to handle game-day decisions.")
                        case .gmAndHeadCoach:
                            Text("Full control. Manage the roster and make coaching decisions including scheme selection and game-day strategy.")
                        }
                    }
                }

                // MARK: - Cap Mode
                Section {
                    Picker("Salary Cap", selection: $selectedCapMode) {
                        Text("Simple").tag(CapMode.simple)
                        Text("Realistic").tag(CapMode.realistic)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.backgroundSecondary)
                } header: {
                    Text("Salary Cap Mode")
                } footer: {
                    Group {
                        switch selectedCapMode {
                        case .simple:
                            Text("Streamlined cap management. Contracts are straightforward annual salaries with no dead cap or restructuring.")
                        case .realistic:
                            Text("Full NFL salary cap rules including signing bonuses, dead cap, restructures, franchise tags, and cap rollover.")
                        }
                    }
                }

                // MARK: - Team Selection
                Section {
                    NavigationLink(destination: TeamSelectionView(
                        playerName: playerName,
                        avatarID: selectedAvatarID,
                        selectedRole: selectedRole,
                        selectedCapMode: selectedCapMode
                    )) {
                        HStack {
                            Image(systemName: "sportscourt.fill")
                                .foregroundStyle(Color.accentGold)
                            Text("Choose Your Team")
                                .font(.headline)
                        }
                    }
                    .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("New Career")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        NewCareerView()
    }
    .modelContainer(for: Career.self, inMemory: true)
}
