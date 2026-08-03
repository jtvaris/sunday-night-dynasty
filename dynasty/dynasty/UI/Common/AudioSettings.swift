import Foundation

/// The two audio volume settings, in one place.
///
/// There are three readers of each level — the Settings slider, the director
/// that applies it, and Settings' "Delete All Save Data" re-seed — and before
/// this type they each carried their own literal. That is a silent-drift bug
/// waiting to happen: the sliders would still work, the reset would still
/// reset, and a fresh install would simply come up at a level nobody chose.
///
/// **These are app settings, not career settings.** They are deliberately NOT
/// in `CareerScopedDefaults.keys`: how loud someone wants their device is a
/// property of the device and the person, not of the save they happen to have
/// open, and a player who turns the music down in one career should not find
/// it loud again in the next.
///
/// Changing a default here only affects installs that have never written the
/// key. `UserDefaults.object(forKey:)` returns nil in exactly that case, which
/// is why both directors read through `object` and coalesce rather than using
/// `double(forKey:)` — that returns 0 for a missing key and would be
/// indistinguishable from a player who slid the control to silence.
enum AudioSettings {

    /// Fresh-install music level (0…1).
    ///
    /// Lowered from 0.5 after the user reported the game arriving too loud.
    /// The score is background by definition — it plays under the UI for the
    /// whole time a career is open, and `MusicContext.levelTrim` then takes a
    /// further 0.50-0.85 off depending on the screen, so this is the top of a
    /// chain rather than the final level.
    static let musicVolumeDefault: Double = 0.35

    /// Fresh-install game-sounds level (0…1) — crowd bed, contact, whistles,
    /// horns, every ``MatchSound``.
    ///
    /// Lowered from 0.7. Kept well above the music default on purpose: during
    /// a coached game the music suspends entirely, so this slider is alone in
    /// the mix and is the thing the player is meant to be hearing.
    static let soundVolumeDefault: Double = 0.6
}
