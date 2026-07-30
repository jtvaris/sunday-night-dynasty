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

    // MARK: - AI photo picks (ExtrasCatalog)

    /// Persona labels for the AI photo headshots, in id order within each
    /// gender. Kept apart from `all` on purpose — `avatarID(for:gender:)` picks
    /// an AI *coach's* placeholder out of `maleAvatars`/`femaleAvatars`, and
    /// these 20 photographs are the USER's own persona set, so they must never
    /// leak into that draw. Labels are written in the same "The X" voice as the
    /// illustrated set and are all distinct from it.
    private static let malePhotoNames = [
        "The Chairman", "The Closer", "The Grinder", "The Technician", "The Firebrand",
        "The Realist", "The Statesman", "The Sergeant", "The Scholar", "The Bulldog",
    ]

    private static let femalePhotoNames = [
        "The Executive", "The Negotiator", "The Chief", "The Diplomat", "The Enforcer",
        "The Modernist", "The Recruiter", "The Competitor", "The Organizer", "The Believer",
    ]

    /// The 20 AI photo choices (`avatar_00000`…`avatar_00019`), gender-split and
    /// id-sorted, labelled from the two lists above.
    ///
    /// EMPTY when the extras manifest did not ship — the picker then shows only
    /// the illustrated set and nothing else changes. That is the whole fallback
    /// story for this feature (`ExtrasCatalog`).
    static let photoAvatars: [CoachAvatarInfo] = {
        let byGender: [(FacePersonGender, [String], CoachAvatarInfo.Gender)] = [
            (.male, malePhotoNames, .male),
            (.female, femalePhotoNames, .female),
        ]
        return byGender.flatMap { gender, names, infoGender in
            ExtrasCatalog.shared.avatars(gender: gender).enumerated().map { index, entry in
                CoachAvatarInfo(
                    id: entry.id,
                    // More photos than labels would fall off the end of the list;
                    // wrap instead, so a regenerated set of any size still shows
                    // a name under every face.
                    name: names.isEmpty ? "Portrait" : names[index % names.count],
                    gender: infoGender
                )
            }
        }
    }()

    static let malePhotoAvatars: [CoachAvatarInfo] = photoAvatars.filter { $0.gender == .male }
    static let femalePhotoAvatars: [CoachAvatarInfo] = photoAvatars.filter { $0.gender == .female }

    /// Looks an id up across BOTH families, so `NewCareerView` can print the
    /// persona label of whatever the user tapped.
    static func avatar(for id: String) -> CoachAvatarInfo? {
        all.first { $0.id == id } ?? photoAvatars.first { $0.id == id }
    }
}

// MARK: - Avatar Selection Grid

struct AvatarSelectionView: View {
    @Binding var selectedAvatarID: String
    var avatarSize: CGFloat = 72
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Male coaches — #109: subtler divider style
            genderDivider(label: "Male")

            LazyVGrid(columns: columns, spacing: 12) {
                // The AI photo headshots lead each gender group: they are the
                // better-looking option and the illustrated set stays right
                // below, unchanged, for anyone who prefers it. Both write the
                // same `Career.avatarID`, so nothing downstream cares which
                // family was picked.
                ForEach(CoachAvatars.malePhotoAvatars) { avatar in
                    avatarCell(avatar)
                }
                ForEach(CoachAvatars.maleAvatars) { avatar in
                    avatarCell(avatar)
                }
            }

            // Female coaches — #109: subtler divider style
            genderDivider(label: "Female")
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CoachAvatars.femalePhotoAvatars) { avatar in
                    avatarCell(avatar)
                }
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

            // #105: larger avatar name
            Text(avatar.name)
                .font(.caption.weight(.medium))
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

    // #109: Thin divider with label instead of bold header
    private func genderDivider(label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
                .frame(maxWidth: 20)

            Text(label)
                .font(.caption2.weight(.regular))
                .foregroundStyle(Color.textTertiary)

            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
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
