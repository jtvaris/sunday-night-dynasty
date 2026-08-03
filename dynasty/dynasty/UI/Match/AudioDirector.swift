import AVFoundation
import UIKit

// MARK: - Match Sound Vocabulary

/// The SFX bundled under Resources/Audio. Most cues are now RECORDED material
/// shipped by `tools/audio/ship_audio.py` — Sonniss GDC stadium captures for
/// the crowd and Stable Audio Open generations for the contact/kick/voice
/// one-shots (see LICENSES.md). Two procedural leftovers survive because the
/// recorded set has no equivalent: `snap` and `td_horn`.
///
/// A cue is a *vocabulary word*, not a file: `takes` lists the wavs behind it
/// and `AudioDirector.play` rotates through them without ever repeating the
/// same take twice in a row, so a drive's worth of tackles never sounds like
/// one sample on repeat.
enum MatchSound: String, CaseIterable {
    /// C→QB exchange tick (also the long snap on punts/FGs).
    case snap
    /// Referee pea whistle — the play is dead.
    case whistle
    /// Routine tackle thud.
    case hitLight = "hit_light"
    /// De-cleater: big-hit falls (pairs with a grunt and a crowd reaction).
    case hitBig = "hit_big"
    /// Ball arriving into hands: completions, picks, kick catches.
    case catchPop = "catch_pop"
    /// Generic foot-into-leather. Prefer `kickPlace` / `kickPunt`; this stays
    /// as the safe default for any beat that only knows "a kick happened".
    case kickThump = "kick_thump"
    /// Stadium air-horn riff for touchdowns.
    case tdHorn = "td_horn"
    /// Legacy alias for a crowd rise. Live crowd reactions belong to
    /// ``CrowdReactor`` now — this stays so older beats keep compiling.
    case crowdSwell = "crowd_swell"

    // Recorded additions.

    /// Air off the ball as the passer lets go.
    case throwWhoosh = "throw_whoosh"
    /// Placekick: field goal, extra point, kickoff off the tee.
    case kickPlace = "kick_place"
    /// Punt: the flatter, heavier boot.
    case kickPunt = "kick_punt"
    /// Effort/pain vocalisation layered under a de-cleater.
    case grunt
    /// The QB barking his count — fires occasionally in the pre-snap window.
    case cadence
    /// Crowd reactions. Driven by ``CrowdReactor``, never fired directly from
    /// the choreography.
    case crowdCheer = "crowd_cheer"
    case crowdBoo = "crowd_boo"
    case crowdGasp = "crowd_gasp"
    case crowdChant = "crowd_chant"

    /// The wav files behind this cue. Where intensity is meaningful (the
    /// cheers) they run smallest → biggest, so a caller can ask for a take by
    /// magnitude instead of at random.
    var takes: [String] {
        switch self {
        case .snap:        return ["snap"]
        case .tdHorn:      return ["td_horn"]
        case .whistle:     return ["sfx_whistle_1"]
        case .hitLight,
             .hitBig:      return ["sfx_tackle_1", "sfx_tackle_2"]
        case .catchPop:    return ["sfx_catch_1", "sfx_catch_2", "sfx_catch_3", "sfx_catch_4"]
        case .kickThump,
             .kickPlace:   return ["sfx_kick_place_1", "sfx_kick_place_2", "sfx_kick_place_3"]
        case .kickPunt:    return ["sfx_kick_punt_1", "sfx_kick_punt_2"]
        case .throwWhoosh: return ["sfx_throw_1", "sfx_throw_2"]
        case .grunt:       return ["sfx_grunt_1", "sfx_grunt_2"]
        case .cadence:     return ["sfx_cadence_1"]
        case .crowdSwell:  return ["crowd_cheer_1"]
        case .crowdCheer:  return ["crowd_cheer_1", "crowd_cheer_2", "crowd_cheer_3"]
        case .crowdBoo:    return ["crowd_boo_1", "crowd_boo_2", "crowd_boo_3", "crowd_boo_4"]
        case .crowdGasp:   return ["crowd_gasp_1", "crowd_gasp_2", "crowd_gasp_3"]
        case .crowdChant:  return ["crowd_chant_1", "crowd_chant_2", "crowd_chant_3"]
        }
    }

    /// Per-cue mix level relative to the master volume. The recorded takes are
    /// all mastered to ‑18 LUFS, so this is pure musical balance: contact and
    /// whistles sit on top, air and voice tuck under the action.
    var gain: Float {
        switch self {
        case .snap:        return 0.7
        case .whistle:     return 0.85
        case .hitLight:    return 0.75
        case .hitBig:      return 0.95
        case .catchPop:    return 0.8
        case .kickThump,
             .kickPlace,
             .kickPunt:    return 0.85
        case .throwWhoosh: return 0.5    // a hint of air, not a lightsaber
        case .grunt:       return 0.6
        case .cadence:     return 0.55   // background colour, never a lyric
        case .tdHorn:      return 0.8
        case .crowdSwell,
             .crowdCheer,
             .crowdBoo,
             .crowdGasp,
             .crowdChant:  return 0.9
        }
    }

    /// Simultaneous voices kept warm per FILE. Hits can overlap on gang
    /// tackles; the long one-shot moments never stack.
    var poolSize: Int {
        switch self {
        case .tdHorn, .whistle, .cadence,
             .crowdSwell, .crowdCheer, .crowdBoo, .crowdGasp, .crowdChant:
            return 1
        default:
            return 2
        }
    }
}

// MARK: - AudioDirector

/// Lightweight playback hub for the live 3D match: a preloaded
/// `AVAudioPlayer` pool per wav plus a looping crowd bed whose volume
/// follows the game situation. Triggers come from the choreography
/// (`FootballFieldScene.execute(step:)`), from `CoachedGameView` at play
/// resolution, and from ``CrowdReactor`` for the reaction layer.
///
/// Design constraints honored here:
/// - `.ambient` session with `.mixWithOthers`: respects the ring/silent
///   switch and never interrupts the user's own music/podcasts.
/// - Zero allocation on the play path: every player is created once in
///   `preload()`; `play(_:)` only picks an idle pooled voice.
/// - No format assumptions: `AVAudioPlayer(contentsOf:)` decodes whatever the
///   ship script wrote, so mono one-shots and stereo crowd swells coexist.
/// - "Sound" toggle + volume slider live in Settings (UserDefaults keys
///   `soundEnabled` / `soundVolume`) and are re-read on every trigger so
///   changes apply immediately, including silencing the crowd loop.
final class AudioDirector {

    static let shared = AudioDirector()

    // MARK: Tuning

    /// Share of scrimmage snaps that get an audible QB count. Every snap
    /// would turn the cadence into wallpaper within a quarter.
    private static let cadenceChance = 0.4
    /// How far the bed drops (multiplier) while a crowd reaction plays.
    private static let duckAmount: Float = 0.45

    // MARK: State

    /// Warm voices keyed by wav name — cues that share a take share its pool.
    private var voices: [String: [AVAudioPlayer]] = [:]
    /// Index of the take each cue used last, so the next pick can avoid it.
    private var lastTake: [MatchSound: Int] = [:]
    private var crowdPlayer: AVAudioPlayer?
    private var loaded = false
    /// True between `startMatch()` and `endMatch()` — the crowd bed should
    /// be audible (subject to the Settings toggle) whenever this holds.
    private var matchActive = false
    /// Last situation-driven crowd intensity (0…1), kept so a Settings
    /// change or foreground return can restore the correct loudness.
    private var crowdIntensity: Double = 0.5
    /// Bed attenuation while a reaction is on top (1 = unducked). Folded into
    /// `applyCrowdState` so a mid-duck Settings change still resolves right.
    private var bedDuck: Float = 1
    /// Generation counter so a stale un-duck can't undo a newer duck.
    private var duckGeneration = 0

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }

    private var masterVolume: Float {
        let stored = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.7
        return Float(min(max(stored, 0), 1))
    }

    // MARK: Lifecycle

    private init() {
        // Ambient + mixWithOthers: game audio ducks under nothing, obeys
        // the mute switch, and coexists with Music/podcasts. Never fails
        // hard — audio is presentation only.
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

    /// Loads every pooled voice and the crowd loop. Called once when a live
    /// match begins (and lazily from `play` as a safety net) so no file IO
    /// or allocation happens mid-play.
    func preload() {
        guard !loaded else { return }
        loaded = true
        for cue in MatchSound.allCases {
            for take in cue.takes where voices[take] == nil {
                guard let url = Self.assetURL(named: take) else {
                    #if DEBUG
                    print("AudioDirector: missing asset \(take).wav")
                    #endif
                    continue
                }
                var pool: [AVAudioPlayer] = []
                for _ in 0..<cue.poolSize {
                    guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                    player.prepareToPlay()
                    pool.append(player)
                }
                voices[take] = pool
            }
        }
        // The recorded 80 s stadium murmur; the old 8 s procedural loop is
        // the fallback if the ship script has not been run in this checkout.
        let bedURL = Self.assetURL(named: "crowd_bed_talking") ?? Self.assetURL(named: "crowd_loop")
        if let url = bedURL, let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            crowdPlayer = player
        }
    }

    /// Resolves a bundled wav whether the synchronized group flattened the
    /// Audio folder into the bundle root or preserved it as a subdirectory.
    private static func assetURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }

    // MARK: One-shot cues

    /// Fires a cue from a warm pooled voice and returns how long it will
    /// sound (0 when nothing played). Safe to call from any play beat —
    /// returns silently when sound is off or the asset is missing.
    ///
    /// - Parameters:
    ///   - gainScale: multiplies the cue's mix level for this hit only —
    ///     how a caller says "same cue, smaller moment".
    ///   - preferTake: index into ``MatchSound/takes``, clamped. nil picks at
    ///     random while never repeating the previous take.
    @discardableResult
    func play(_ cue: MatchSound, gainScale: Float = 1, preferTake: Int? = nil) -> TimeInterval {
        guard soundEnabled else { return 0 }
        if !loaded { preload() }
        let takes = cue.takes
        guard !takes.isEmpty else { return 0 }

        let index: Int
        if let wanted = preferTake {
            index = min(max(wanted, 0), takes.count - 1)
        } else if takes.count == 1 {
            index = 0
        } else {
            // Never the same take twice running: draw from the others.
            let previous = lastTake[cue]
            let choices = takes.indices.filter { $0 != previous }
            index = choices.randomElement() ?? 0
        }
        lastTake[cue] = index

        guard let pool = voices[takes[index]], !pool.isEmpty else { return 0 }
        let voice = pool.first { !$0.isPlaying } ?? pool[0]
        voice.currentTime = 0
        voice.volume = cue.gain * masterVolume * max(0, gainScale)
        voice.play()
        return voice.duration
    }

    /// The QB's count, on roughly 40 % of scrimmage snaps. Call it in the
    /// pre-snap window; it bleeds a little past the snap on purpose, the way
    /// a real cadence does.
    func playCadence() {
        guard Double.random(in: 0..<1) < Self.cadenceChance else { return }
        play(.cadence)
    }

    // MARK: Crowd bed

    /// Starts the ambient stadium loop for a live match.
    func startMatch(initialIntensity: Double = 0.5) {
        preload()
        matchActive = true
        crowdIntensity = initialIntensity
        bedDuck = 1
        applyCrowdState(fade: 0.8)
    }

    /// Fades the crowd out and releases the field — call when the match
    /// view disappears.
    func endMatch() {
        matchActive = false
        bedDuck = 1
        crowdPlayer?.setVolume(0, fadeDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.matchActive else { return }
            self.crowdPlayer?.pause()
        }
    }

    /// Situation-driven loudness (0…1): home crowd, score margin, red zone
    /// and crunch time all feed in from `CoachedGameView`. Ramped, never
    /// snapped, so drives breathe instead of clicking between levels.
    func setCrowdIntensity(_ intensity: Double) {
        crowdIntensity = min(max(intensity, 0), 1)
        applyCrowdState(fade: 1.2)
    }

    /// Pulls the bed down under a crowd reaction and lets it back up when the
    /// reaction has run its course. ``CrowdReactor`` owns the timing; a newer
    /// duck always wins over an older one's restore.
    func duckCrowdBed(for duration: TimeInterval) {
        guard matchActive else { return }
        duckGeneration += 1
        let generation = duckGeneration
        bedDuck = Self.duckAmount
        applyCrowdState(fade: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.duckGeneration == generation else { return }
            self.bedDuck = 1
            self.applyCrowdState(fade: 1.0)
        }
    }

    /// Reconciles the crowd player with (enabled × active × intensity × duck).
    private func applyCrowdState(fade: TimeInterval) {
        guard let crowd = crowdPlayer else { return }
        guard matchActive, soundEnabled else {
            if crowd.isPlaying { crowd.setVolume(0, fadeDuration: 0.3) }
            return
        }
        if !crowd.isPlaying { crowd.play() }
        // Bed sits well under the SFX: 15 % floor rising to ~60 % of master.
        let target = masterVolume * Float(0.15 + 0.45 * crowdIntensity) * bedDuck
        crowd.setVolume(target, fadeDuration: fade)
    }

    // MARK: App / session transitions

    @objc private func appDidEnterBackground() {
        // Ambient audio has no background entitlement — park the loop
        // cleanly instead of letting the session cut it mid-buffer.
        crowdPlayer?.pause()
    }

    @objc private func appWillEnterForeground() {
        guard matchActive else { return }
        applyCrowdState(fade: 0.8)
    }

    @objc private func settingsChanged() {
        // Sound toggle / volume slider apply live, mid-game included.
        applyCrowdState(fade: 0.4)
    }

    @objc private func sessionInterrupted(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            crowdPlayer?.pause()
        case .ended:
            if matchActive { applyCrowdState(fade: 0.8) }
        @unknown default:
            break
        }
    }
}
