import AVFoundation
import UIKit

// MARK: - Music Contexts

/// Where in the game the player is, from the soundtrack's point of view.
///
/// These are not screens and not `SeasonPhase` values — they are the seven
/// moods the score actually distinguishes. Several phases collapse onto
/// `dashboard` on purpose: OTAs and the trade deadline want the same
/// understated bed, and giving each its own playlist would only mean thinner
/// rotations and more repeats.
enum MusicContext: String, CaseIterable {

    /// Title screen. The two takes the player already knows plus one more.
    case menu
    /// The career shell in ordinary weeks — front office background.
    case dashboard
    /// The draft room, clock ticking.
    case draft
    /// Game-week prep and the game plan, right up to kickoff.
    case gameday
    /// January. Same instruments as `menu`, colder key.
    case playoffs
    /// The Super Bowl phase and the trophy.
    case championship
    /// Coaching changes, roster review, free agency — the quiet months.
    case offseason

    /// The playlist, in the order the shuffle bag is built from.
    ///
    /// `plays` is how many times a file runs before the silence gap. The
    /// ambient beds are 40-45 s seamless loops (their wrap point was measured,
    /// see `post_music.py`), so they are played through several times to make
    /// a stretch of music rather than a 45 s fragment; the through-composed
    /// themes are 2-3 minutes and always play once.
    var entries: [(file: String, plays: Int)] {
        switch self {
        case .menu:
            return [("music_menu_theme_a", 1),
                    ("music_menu_theme_b", 1),
                    ("music_menu_theme_c", 1)]
        case .dashboard:
            return [("music_dashboard_loop_a", 3),
                    ("music_dashboard_loop_b", 3),
                    ("music_dashboard_loop_c", 3),
                    ("music_dashboard_loop_d", 3),
                    ("music_dashboard_loop_e", 3),
                    ("music_dashboard_bed_a", 1),
                    ("music_dashboard_bed_b", 1),
                    ("music_dashboard_bed_c", 1),
                    ("music_dashboard_bed_d", 1)]
        case .draft:
            return [("music_draft_a", 1),
                    ("music_draft_b", 1),
                    ("music_draft_c", 1)]
        case .gameday:
            return [("music_gameday_a", 1),
                    ("music_gameday_b", 1),
                    ("music_gameday_c", 1),
                    ("music_gameday_d", 1),
                    ("music_gameday_e", 1)]
        case .playoffs:
            return [("music_playoffs_a", 1),
                    ("music_playoffs_b", 1),
                    ("music_playoffs_c", 1)]
        case .championship:
            return [("music_championship_a", 1),
                    ("music_championship_b", 1)]
        case .offseason:
            // Shares the approved lo-fi bed with the dashboard rather than
            // shipping the same audio twice under a second name.
            return [("music_offseason_loop_a", 3),
                    ("music_offseason_loop_b", 3),
                    ("music_dashboard_loop_b", 3)]
        }
    }

    /// Silence between tracks, in seconds. Background music that never stops
    /// stops being background — it becomes a thing the player is enduring.
    /// The dashboard is where someone spends the most uninterrupted time, so
    /// it gets the longest breathing room (the brief's 30-90 s); the
    /// event screens are short-lived and get tighter gaps so a cue is not
    /// mostly silence.
    var gapRange: ClosedRange<TimeInterval> {
        switch self {
        case .dashboard:    return 30...90
        case .offseason:    return 30...90
        case .menu:         return 8...20
        case .draft:        return 6...16
        case .gameday:      return 4...12
        case .playoffs:     return 6...15
        case .championship: return 3...8
        }
    }

    /// Per-context trim on top of the user's music volume. Everything was
    /// mastered to the same −16 LUFS, so this is pure balance: the ambient
    /// beds tuck under the UI, the trophy moment is allowed to be loud.
    var levelTrim: Float {
        switch self {
        case .menu:         return 0.75
        case .dashboard:    return 0.55
        case .draft:        return 0.60
        case .gameday:      return 0.80
        case .playoffs:     return 0.75
        case .championship: return 0.85
        case .offseason:    return 0.50
        }
    }
}

// MARK: - MusicDirector

/// The soundtrack. One `AVAudioPlayer` at a time, a shuffled no-repeat bag per
/// context, and a deliberate silence gap between tracks.
///
/// Deliberately separate from ``AudioDirector`` rather than folded into it:
/// - the SFX director keeps a preloaded pool warm because a tackle must not
///   wait for file IO. Music is the opposite — one stream, decoded lazily,
///   and a few hundred ms of latency at a track change is invisible.
/// - music has its own Settings toggle and volume. A player who wants crowd
///   noise but no score (or the reverse) can have it.
///
/// Context is resolved as `override ?? base`. The career shell sets the *base*
/// from `SeasonPhase`; individual screens that want their own score for as
/// long as they are on top (the draft room, the game plan) push an *override*
/// and clear it on disappear. That means no screen has to know what to restore
/// the music to — it only has to know what it wants while it is visible.
///
/// The live coached game is a third state: ``suspend()`` stops the music
/// entirely so `AudioDirector`'s crowd bed and the play SFX have the mix to
/// themselves, and ``resume()`` puts it back when the match view goes away.
final class MusicDirector: NSObject, AVAudioPlayerDelegate {

    static let shared = MusicDirector()

    // MARK: Tuning

    private static let fadeIn: TimeInterval = 2.0
    private static let fadeOut: TimeInterval = 1.5
    /// Delay after a fade-out before the next track is allowed to start, so a
    /// context switch is never two tracks overlapping.
    private static let switchGap: TimeInterval = 0.4

    // MARK: State

    private var player: AVAudioPlayer?
    private var baseContext: MusicContext?
    private var overrideContext: MusicContext?
    /// True while the live match owns the mix.
    private var suspended = false
    /// Remaining shuffled picks for the active context; refilled when empty.
    private var bag: [String] = []
    private var bagContext: MusicContext?
    /// Last file played in this context, so a refilled bag never opens with a
    /// repeat of the track that just finished.
    private var lastFile: String?
    /// Pending "start the next track" work, cancelled on every state change so
    /// a stale gap timer cannot fire music into a context that has moved on.
    private var pendingStart: DispatchWorkItem?
    private var isForeground = true

    private var effectiveContext: MusicContext? {
        overrideContext ?? baseContext
    }

    private var musicEnabled: Bool {
        UserDefaults.standard.object(forKey: "musicEnabled") as? Bool ?? true
    }

    private var musicVolume: Float {
        let stored = UserDefaults.standard.object(forKey: "musicVolume") as? Double ?? 0.5
        return Float(min(max(stored, 0), 1))
    }

    /// Target volume for the active context (0 when music should be silent).
    private var targetVolume: Float {
        guard musicEnabled, !suspended, let ctx = effectiveContext else { return 0 }
        return musicVolume * ctx.levelTrim
    }

    // MARK: Lifecycle

    private override init() {
        super.init()
        // Same session policy as AudioDirector: ambient + mixWithOthers, so
        // the score obeys the silent switch and never interrupts the user's
        // own music. Setting it twice is harmless and neither director can
        // assume it ran first.
        try? AVAudioSession.sharedInstance()
            .setCategory(.ambient, options: [.mixWithOthers])

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionInterrupted(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: AVAudioSession.sharedInstance())
    }

    // MARK: Context

    /// The phase-driven default, owned by `CareerShellView`. Safe to call on
    /// every phase change — a repeat of the current base is ignored, so the
    /// track playing through a week advance is not restarted.
    func setBaseContext(_ context: MusicContext?) {
        guard baseContext != context else { return }
        let before = effectiveContext
        baseContext = context
        if effectiveContext != before { restart() }
    }

    /// Claim the soundtrack while a particular screen is on top.
    func pushOverride(_ context: MusicContext) {
        guard overrideContext != context else { return }
        let before = effectiveContext
        overrideContext = context
        if effectiveContext != before { restart() }
    }

    /// Release a screen's claim. The `context` argument makes this safe to
    /// call from `onDisappear` after another screen has already taken over:
    /// a view can only clear the override it set.
    func clearOverride(_ context: MusicContext) {
        guard overrideContext == context else { return }
        let before = effectiveContext
        overrideContext = nil
        if effectiveContext != before { restart() }
    }

    /// Stop the score for the live coached game. The match has its own audio
    /// world — crowd bed, contact, whistles — and a menu theme underneath it
    /// would fight everything `AudioDirector` is doing.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        stop(fade: Self.fadeOut)
    }

    /// Give the score back after the match view goes away.
    func resume() {
        guard suspended else { return }
        suspended = false
        restart()
    }

    // MARK: Playback

    /// Tear down whatever is playing and begin the effective context afresh.
    private func restart() {
        stop(fade: Self.fadeOut)
        bag = []
        bagContext = nil
        lastFile = nil
        guard targetVolume > 0, isForeground else { return }
        schedule(after: Self.switchGap)
    }

    private func stop(fade: TimeInterval) {
        pendingStart?.cancel()
        pendingStart = nil
        guard let current = player else { return }
        player = nil
        current.delegate = nil
        current.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) {
            current.stop()
        }
    }

    /// Queue the next track. Any previously queued start is cancelled, so the
    /// most recent decision always wins.
    private func schedule(after delay: TimeInterval) {
        pendingStart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.playNext() }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func playNext() {
        pendingStart = nil
        guard let ctx = effectiveContext, targetVolume > 0, isForeground else { return }

        guard let entry = nextEntry(for: ctx) else { return }
        guard let url = Self.assetURL(named: entry.file) else {
            #if DEBUG
            print("MusicDirector: missing track \(entry.file).m4a")
            #endif
            // Do not stall the whole playlist on one missing file — drop it
            // and try the next pick on the normal gap cadence.
            schedule(after: 1.0)
            return
        }
        guard let next = try? AVAudioPlayer(contentsOf: url) else {
            schedule(after: 1.0)
            return
        }

        lastFile = entry.file
        next.delegate = self
        // `numberOfLoops` is repeats-after-the-first, hence the -1.
        next.numberOfLoops = max(0, entry.plays - 1)
        next.volume = 0
        next.prepareToPlay()
        next.play()
        next.setVolume(targetVolume, fadeDuration: Self.fadeIn)
        player = next
    }

    /// Draw from the shuffle bag, refilling it when empty. Two guarantees:
    /// every track in a context plays once before any track plays twice, and
    /// the join between two bags never repeats a track back-to-back.
    private func nextEntry(for ctx: MusicContext) -> (file: String, plays: Int)? {
        let entries = ctx.entries
        guard !entries.isEmpty else { return nil }

        if bagContext != ctx || bag.isEmpty {
            bagContext = ctx
            bag = entries.map { $0.file }.shuffled()
            // Only worth fixing when there is somewhere else to go.
            if bag.count > 1, bag.first == lastFile {
                bag.swapAt(0, bag.count - 1)
            }
        }
        let file = bag.removeFirst()
        return entries.first { $0.file == file }
    }

    /// Resolves a bundled track whether the synchronized group preserved the
    /// Audio/Music folders or flattened them into the bundle root.
    private static func assetURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Audio/Music")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Music")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ audioPlayer: AVAudioPlayer, successfully flag: Bool) {
        guard audioPlayer === player else { return }
        player = nil
        guard let ctx = effectiveContext else { return }
        schedule(after: TimeInterval.random(in: ctx.gapRange))
    }

    func audioPlayerDecodeErrorDidOccur(_ audioPlayer: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else { return }
        player = nil
        schedule(after: 2.0)
    }

    // MARK: App / session transitions

    @objc private func appDidEnterBackground() {
        isForeground = false
        pendingStart?.cancel()
        pendingStart = nil
        player?.pause()
    }

    @objc private func appWillEnterForeground() {
        isForeground = true
        guard targetVolume > 0 else { return }
        if let current = player {
            current.play()
            current.setVolume(targetVolume, fadeDuration: 1.0)
        } else if effectiveContext != nil {
            schedule(after: Self.switchGap)
        }
    }

    @objc private func settingsChanged() {
        // Toggle and slider apply live. Turning music off fades the current
        // track out; turning it back on restarts the rotation rather than
        // resuming mid-track, which would sound like a glitch.
        let target = targetVolume
        if target <= 0 {
            stop(fade: Self.fadeOut)
        } else if player == nil && pendingStart == nil {
            restart()
        } else {
            player?.setVolume(target, fadeDuration: 0.4)
        }
    }

    @objc private func sessionInterrupted(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            player?.pause()
        case .ended:
            guard targetVolume > 0, isForeground else { return }
            player?.play()
        @unknown default:
            break
        }
    }
}

// MARK: - Season phase mapping

extension MusicContext {

    /// The base context for a career sitting in `phase`.
    ///
    /// Everything that is not a distinct *moment* falls through to
    /// `dashboard`. That is the point: the score should mark the draft, the
    /// playoffs and the trophy, and otherwise stay out of the way.
    static func forPhase(_ phase: SeasonPhase) -> MusicContext {
        switch phase {
        case .draft:
            return .draft
        case .playoffs:
            return .playoffs
        case .superBowl:
            return .championship
        case .coachingChanges, .reviewRoster, .freeAgency:
            return .offseason
        case .proBowl, .combine, .proDays, .otas, .trainingCamp,
             .preseason, .rosterCuts, .regularSeason, .tradeDeadline:
            return .dashboard
        }
    }
}
