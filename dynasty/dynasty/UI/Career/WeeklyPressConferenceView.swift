import SwiftUI

// MARK: - WeeklyPressConferenceView — the post-game mount point (#105 Wave 5a)
//
// UI_REDESIGN_VISION §4 Wave 5: *"Merge the two press-conference views … then
// restyle the survivors."* The merge happened in `PressConferenceView`, which is
// now the app's only press-conference implementation and carries both openings
// as a ``PressConferenceView/Session``.
//
// This type survives as a **name, not a second implementation**. `CareerShellView`
// presents `WeeklyPressConferenceView(questions:career:context:owner:onComplete:)` from
// a `fullScreenCover`, and that file belongs to another lane of this wave — so
// the call site keeps its signature and this adapter forwards it. Nothing here
// draws anything, computes anything, or knows anything about the presser; it is
// eight lines of plumbing over the merged screen.
//
// If a later wave owns `CareerShellView`, the mount can point straight at
// `PressConferenceView(questions:career:context:onComplete:)` and this file goes
// away entirely.

struct WeeklyPressConferenceView: View {

    let questions: [PressQuestion]
    let career: Career
    /// #161: the context `WeekAdvancer` assembled next to the questions —
    /// situation, standing, locker-room band, owner persona, tone ledger. It is
    /// passed straight through, so the weekly presser and the intro presser
    /// cannot drift apart mechanically.
    var context: PressConferenceEngine.PressContext = .neutral
    /// #177: the club's owner, and the reason this adapter is not a pure
    /// pass-through of four arguments.
    ///
    /// The merged screen's standing strip promises "BEFORE THIS SESSION ·
    /// Legacy / Media / **Satisfaction**", and its summary promises an
    /// `owner satisfaction baseline \u{2192} final` reading. Both are drawn only
    /// `if let owner`, and the post-game initializer defaults `owner` to nil —
    /// so every weekly presser in the game silently dropped the owner column
    /// while the intro presser kept it. The two openings were supposed to be
    /// mechanically identical after the merge; this is the one input that was
    /// still wired to only one of them.
    var owner: Owner?
    let onComplete: (PressConferenceResult) -> Void

    var body: some View {
        PressConferenceView(
            questions: questions,
            career: career,
            context: context,
            owner: owner,
            onComplete: onComplete
        )
    }
}

// MARK: - Preview

#Preview("Post-game") {
    WeeklyPressConferenceView(
        questions: PressConferenceEngine.generateWeeklyPressConference(
            career: Career(
                playerName: "Mike Johnson",
                avatarID: "avatar_00000",
                role: .gmAndHeadCoach,
                capMode: .simple
            ),
            team: Team(
                name: "Stockyards",
                city: "Kansas City",
                abbreviation: "KC",
                conference: .AFC,
                division: .west,
                mediaMarket: .large,
                owner: Owner(name: "Merrill Ashford")
            ),
            lastGameResult: true,
            week: 5
        ),
        career: Career(
            playerName: "Mike Johnson",
            avatarID: "avatar_00000",
            role: .gmAndHeadCoach,
            capMode: .simple
        ),
        onComplete: { _ in }
    )
}
