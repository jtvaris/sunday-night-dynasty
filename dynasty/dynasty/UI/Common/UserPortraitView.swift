import SwiftUI

// MARK: - UserPortrait catalog

/// The user's own head-coach portrait: which photographs may be chosen, how a
/// stored choice resolves, and what each one is called.
///
/// The player picks one of the 20 AI headshots (`avatar_00000`…`avatar_00019`,
/// `ExtrasCatalog`) when the career is created, and that id is written to
/// `Career.avatarID` — a per-`Career` stored property, so the choice is
/// careerID-scoped by construction and two saves never share a face.
///
/// ## Why nothing here can return an illustration
///
/// The picker used to offer a second family — 20 hand-drawn `coach_m*`/`coach_f*`
/// asset-catalog portraits — and `Career.avatarID` defaulted to `coach_m1`. Quick
/// Start skips the identity step entirely, so *every* Quick Start career kept
/// that default and the staff screen drew a cartoon next to 52 photographed
/// players. The illustrations are gone; `resolve` maps any surviving id from an
/// old save onto a photograph deterministically, so a career created before this
/// change gets a real face and keeps the same one forever.
enum UserPortrait {

    /// Every choosable portrait id, sorted (`ExtrasCatalog` sorts by id).
    /// Empty only when the extras did not ship.
    static var all: [String] { ExtrasCatalog.shared.avatars.map(\.id) }

    /// What a career falls back to when nothing better is known.
    static var fallbackID: String { all.first ?? "avatar_00000" }

    // MARK: - Persona labels

    /// Persona label lists, applied in id order **within each gender** — the
    /// same voice the old illustrated set used, and all distinct from it.
    private static let malePhotoNames = [
        "The Chairman", "The Closer", "The Grinder", "The Technician", "The Firebrand",
        "The Realist", "The Statesman", "The Sergeant", "The Scholar", "The Bulldog",
    ]

    private static let femalePhotoNames = [
        "The Executive", "The Negotiator", "The Chief", "The Diplomat", "The Enforcer",
        "The Modernist", "The Recruiter", "The Competitor", "The Organizer", "The Believer",
    ]

    /// id → persona label, built once from the manifest's gender buckets. A pool
    /// larger than the label list wraps rather than falling off the end, so a
    /// regenerated set of any size still shows a name under every face.
    private static let labels: [String: String] = {
        var map: [String: String] = [:]
        for (gender, names) in [
            (FacePersonGender.male, malePhotoNames),
            (FacePersonGender.female, femalePhotoNames),
        ] {
            guard !names.isEmpty else { continue }
            for (index, entry) in ExtrasCatalog.shared.avatars(gender: gender).enumerated() {
                map[entry.id] = names[index % names.count]
            }
        }
        return map
    }()

    /// The persona label for a portrait id, or `nil` for an id the manifest does
    /// not know (a legacy `coach_*` value, or a build without the extras).
    static func label(for id: String) -> String? { labels[id] }

    // MARK: - Resolution

    /// The photograph a career actually renders.
    ///
    /// - Parameters:
    ///   - storedID: whatever `Career.avatarID` holds — a photo id, a legacy
    ///     illustration id, or junk.
    ///   - seed: the career's own UUID. A legacy/unknown id maps onto a
    ///     photograph through this, so the substitute is stable for the life of
    ///     the save instead of moving on every launch.
    /// - Returns: a bundled portrait id, or `nil` when the extras did not ship
    ///   (the caller then draws a monogram — never an illustration).
    static func resolve(_ storedID: String?, seed: UUID?) -> String? {
        let ids = all
        if let storedID, ExtrasCatalog.isAvatarID(storedID) {
            // An unloaded manifest still renders a saved photo id: the HEIC
            // lookup is by filename and does not need the manifest at all.
            if ids.isEmpty || ids.contains(storedID) { return storedID }
        }
        guard !ids.isEmpty else { return nil }
        guard let seed else { return ids[0] }
        return ids[Int(FaceLibrary.stableHash(seed) % UInt64(ids.count))]
    }

    /// Whether a stored value is already one of the choosable photographs.
    static func isPortraitID(_ id: String) -> Bool {
        ExtrasCatalog.isAvatarID(id) && (all.isEmpty || all.contains(id))
    }

    // MARK: - Picker order

    /// The choices in a reproducible pseudo-random order.
    ///
    /// The pool is exactly 20 and the picker shows 20, so this shuffles rather
    /// than samples — every face is always reachable, and "random" only means the
    /// grid does not open with the same portrait in the top-left every career.
    /// A larger pool would take the first 20 of the shuffle, which is why the cap
    /// is applied here and not left to the view.
    static func shuffled(seed: UInt64, limit: Int = 20) -> [String] {
        var pool = all
        guard pool.count > 1 else { return pool }
        // Fisher-Yates over a small LCG, so the same seed always produces the
        // same grid (a redraw of the view must not reshuffle under the finger).
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func next(_ upperBound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(upperBound))
        }
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, next(i + 1))
        }
        return Array(pool.prefix(limit))
    }

    /// A fresh order seed. Used once per new career and once per reshuffle tap.
    static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }

    /// The portrait a brand-new career opens on: the first face of a fresh
    /// shuffle, so the wizard never lands on `avatar_00000` every single time.
    static func randomStartingID() -> String {
        shuffled(seed: newSeed()).first ?? fallbackID
    }
}

// MARK: - UserPortraitView

/// The user's own portrait, wherever the game refers to the player.
///
/// One component so every surface — staff card, coaching tree, press podium,
/// owner's office, save slot — resolves `Career.avatarID` the same way and
/// degrades the same way. There is no illustrated fallback: a build without the
/// extras draws the player's initials, which reads as "no photo" rather than as
/// a cartoon standing in for a photograph.
struct UserPortraitView: View {
    /// The stored choice (`Career.avatarID`).
    let avatarID: String
    /// The player's name — VoiceOver label and monogram source.
    let name: String
    /// The career's UUID: stabilises both the legacy-id substitution and the
    /// monogram tint for the life of the save.
    var seed: UUID? = nil
    var size: PersonFaceView.Size = .medium
    /// Gold by default — the user is the one person on screen who is *you*.
    var ringColor: Color? = .accentGold

    /// Stable stand-in when the caller has no career id, so the monogram tint
    /// does not change between frames.
    private static let unseeded = UUID(uuidString: "00000000-0000-0000-0000-0000555E4D00")!

    var body: some View {
        PersonFaceView(
            faceID: UserPortrait.resolve(avatarID, seed: seed),
            size: size,
            ringColor: ringColor,
            accessibilityName: name,
            placeholder: .monogram(
                initials: PersonFaceView.initials(fromFullName: name),
                seed: seed ?? Self.unseeded
            )
        )
    }
}

extension UserPortraitView {
    /// The common call: everything the view needs comes off the career.
    init(career: Career, size: PersonFaceView.Size = .medium, ringColor: Color? = .accentGold) {
        self.init(
            avatarID: career.avatarID,
            name: career.playerName,
            seed: career.id,
            size: size,
            ringColor: ringColor
        )
    }
}

// MARK: - Bundled photo at a free diameter

/// A bundled face HEIC at an arbitrary diameter, decoded through the same
/// `FaceImageCache` every real portrait uses (off the main thread, downscaled
/// once, bounded in bytes).
///
/// `PersonFaceView` covers the three canonical portrait sizes; this exists for
/// the one place that needs a free diameter — the portrait picker's grid, whose
/// cell size is a caller-supplied `CGFloat`. It deliberately shares the cache
/// rather than decoding its own copy, so a picked portrait is already warm
/// everywhere else it appears.
struct BundledFacePhotoView: View {
    let faceID: String
    var size: CGFloat = 80

    @State private var image: UIImage?

    init(faceID: String, size: CGFloat = 80) {
        self.faceID = faceID
        self.size = size
        _image = State(initialValue: FaceImageCache.shared.cachedImage(for: faceID))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                // Same quiet "no photo" disc `PersonFaceView` draws — reached
                // only when the extras HEICs did not ship.
                ZStack {
                    Circle().fill(Color.backgroundTertiary)
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.07)
                        .foregroundStyle(Color.textTertiary.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
        )
        .task(id: faceID) {
            guard image == nil else { return }
            image = await FaceImageCache.shared.loadImage(for: faceID)
        }
    }
}

// MARK: - Portrait picker

/// The career-creation portrait step: 20 photographs, shuffled, one tap to pick.
///
/// The order is seeded and held in state, so the grid is stable while the finger
/// is on it and only moves when "Shuffle" is tapped. Selection is written
/// straight into the binding the wizard hands to `Career.avatarID`.
struct UserPortraitPicker: View {
    @Binding var selectedAvatarID: String
    var avatarSize: CGFloat = 72
    var columnCount: Int = 5

    @State private var seed: UInt64 = UserPortrait.newSeed()

    private var choices: [String] { UserPortrait.shuffled(seed: seed) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if choices.isEmpty {
                // Extras did not ship: say so instead of drawing 20 empty discs.
                Text("Portraits are unavailable in this build.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(choices, id: \.self) { id in
                        portraitCell(id)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            seed = UserPortrait.newSeed()
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reorders the portraits")
                }
            }
        }
        .onAppear {
            // A career carried in from an old save — or the very first frame of
            // a fresh one — must not leave the grid with nothing highlighted.
            if !UserPortrait.isPortraitID(selectedAvatarID) {
                selectedAvatarID = UserPortrait.resolve(selectedAvatarID, seed: nil)
                    ?? UserPortrait.fallbackID
            }
        }
    }

    @ViewBuilder
    private func portraitCell(_ id: String) -> some View {
        let isSelected = selectedAvatarID == id
        VStack(spacing: 4) {
            BundledFacePhotoView(faceID: id, size: avatarSize)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.accentGold : Color.clear,
                        lineWidth: 3
                    )
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: selectedAvatarID)

            Text(UserPortrait.label(for: id) ?? "Portrait")
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentGold : Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(UserPortrait.label(for: id) ?? "Portrait")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contentShape(Rectangle())
        .onTapGesture { selectedAvatarID = id }
    }
}

// MARK: - Change-portrait sheet

/// "Change portrait" from inside a running career — the same picker, wrapped in
/// a sheet that writes straight back to the career on Done.
///
/// Kept separate from the wizard's inline section because the two have different
/// commit semantics: the wizard has not created a `Career` yet, this one edits a
/// live SwiftData model.
struct ChangeUserPortraitSheet: View {
    /// `let`, not `@Bindable`: the only write is `career.avatarID` on Done, and
    /// `Career` is a reference type, so a binding buys nothing — while a `let`
    /// lets the draft state be seeded in `init` rather than in `onAppear`, which
    /// would otherwise race the picker's own `onAppear` normalisation.
    let career: Career
    @Environment(\.dismiss) private var dismiss

    @State private var draftAvatarID: String

    init(career: Career) {
        self.career = career
        _draftAvatarID = State(
            initialValue: UserPortrait.resolve(career.avatarID, seed: career.id)
                ?? UserPortrait.fallbackID
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        UserPortraitView(
                            avatarID: draftAvatarID,
                            name: career.playerName,
                            seed: career.id,
                            size: .large
                        )
                        .padding(.top, 8)

                        Text(UserPortrait.label(for: draftAvatarID) ?? career.playerName)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        UserPortraitPicker(selectedAvatarID: $draftAvatarID, avatarSize: 64)
                            .padding(.horizontal, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Your Portrait")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        career.avatarID = draftAvatarID
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("User portrait") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    UserPortraitView(avatarID: "avatar_00000", name: "Juha Varis", size: .small)
                    UserPortraitView(avatarID: "avatar_00007", name: "Juha Varis", size: .medium)
                    UserPortraitView(avatarID: "avatar_00012", name: "Juha Varis", size: .large)
                    // Legacy illustrated id from an old save — resolves to a photo.
                    UserPortraitView(
                        avatarID: "coach_m1", name: "Mike Johnson",
                        seed: UUID(uuidString: "1D6E0C6A-0000-4000-8000-00000000ABCD"),
                        size: .medium
                    )
                }
                UserPortraitPicker(selectedAvatarID: .constant("avatar_00003"), avatarSize: 64)
                    .padding()
            }
        }
    }
}
