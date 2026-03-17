import SwiftUI

// MARK: - Avatar Data

struct CoachAvatarInfo: Identifiable {
    let id: String
    let name: String
    let gender: Gender

    enum Gender: String { case male, female }
}

// MARK: - All Avatars

enum CoachAvatars {
    static let all: [CoachAvatarInfo] = [
        // Male coaches
        CoachAvatarInfo(id: "coach_m1",  name: "The Veteran",    gender: .male),
        CoachAvatarInfo(id: "coach_m2",  name: "The Strategist", gender: .male),
        CoachAvatarInfo(id: "coach_m3",  name: "The Old School", gender: .male),
        CoachAvatarInfo(id: "coach_m4",  name: "The Motivator",  gender: .male),
        CoachAvatarInfo(id: "coach_m5",  name: "The Innovator",  gender: .male),
        CoachAvatarInfo(id: "coach_m6",  name: "The Professor",  gender: .male),
        CoachAvatarInfo(id: "coach_m7",  name: "The General",    gender: .male),
        CoachAvatarInfo(id: "coach_m8",  name: "The Rookie",     gender: .male),
        CoachAvatarInfo(id: "coach_m9",  name: "The Mentor",     gender: .male),
        CoachAvatarInfo(id: "coach_m10", name: "The Legend",      gender: .male),

        // Female coaches
        CoachAvatarInfo(id: "coach_f1",  name: "The Pioneer",     gender: .female),
        CoachAvatarInfo(id: "coach_f2",  name: "The Analyst",     gender: .female),
        CoachAvatarInfo(id: "coach_f3",  name: "The Trailblazer", gender: .female),
        CoachAvatarInfo(id: "coach_f4",  name: "The Tactician",   gender: .female),
        CoachAvatarInfo(id: "coach_f5",  name: "The Commander",   gender: .female),
        CoachAvatarInfo(id: "coach_f6",  name: "The Visionary",   gender: .female),
        CoachAvatarInfo(id: "coach_f7",  name: "The Maverick",    gender: .female),
        CoachAvatarInfo(id: "coach_f8",  name: "The Prodigy",     gender: .female),
        CoachAvatarInfo(id: "coach_f9",  name: "The Captain",     gender: .female),
        CoachAvatarInfo(id: "coach_f10", name: "The Architect",   gender: .female),
    ]

    static let maleAvatars: [CoachAvatarInfo] = all.filter { $0.gender == .male }
    static let femaleAvatars: [CoachAvatarInfo] = all.filter { $0.gender == .female }

    static func avatar(for id: String) -> CoachAvatarInfo? {
        all.first { $0.id == id }
    }
}

// MARK: - Avatar Selection Grid

struct AvatarSelectionView: View {
    @Binding var selectedAvatarID: String
    var avatarSize: CGFloat = 72
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Male coaches
            Text("Male")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CoachAvatars.maleAvatars) { avatar in
                    avatarCell(avatar)
                }
            }

            // Female coaches
            Text("Female")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CoachAvatars.femaleAvatars) { avatar in
                    avatarCell(avatar)
                }
            }
        }
    }

    @ViewBuilder
    private func avatarCell(_ avatar: CoachAvatarInfo) -> some View {
        VStack(spacing: 4) {
            CoachAvatarImageView(
                avatarID: avatar.id,
                size: avatarSize
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        selectedAvatarID == avatar.id ? Color.accentGold : Color.clear,
                        lineWidth: 3
                    )
            )
            .scaleEffect(selectedAvatarID == avatar.id ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: selectedAvatarID)

            Text(avatar.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(selectedAvatarID == avatar.id ? Color.accentGold : Color.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(avatar.name), \(avatar.gender == .male ? "male" : "female") coach")
        .accessibilityAddTraits(selectedAvatarID == avatar.id ? [.isButton, .isSelected] : .isButton)
        .onTapGesture {
            selectedAvatarID = avatar.id
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        ScrollView {
            AvatarSelectionView(selectedAvatarID: .constant("coach_m1"), avatarSize: 72)
                .padding()
        }
    }
}
