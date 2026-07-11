import AVFoundation
import UIKit

// MARK: - Match Sound Vocabulary

/// The retro procedural SFX bundled under Resources/Audio — every file is
/// synthesized by `tools/asset-pipeline/generate_audio.sh` (ffmpeg sine/
/// noise/filter chains, no recorded material). Raw case value = file name.
enum MatchSound: String, CaseIterable {
    /// C→QB exchange tick (also the long snap on punts/FGs).
    case snap
    /// Referee pea whistle — the play is dead.
    case whistle
    /// Routine tackle thud.
    case hitLight = "hit_light"
    /// De-cleater: big-hit falls (pairs with a crowd swell).
    case hitBig = "hit_big"
    /// Ball arriving into hands: completions, picks, kick catches.
    case catchPop = "catch_pop"
    /// Foot into leather: punts, field goals, kickoffs.
    case kickThump = "kick_thump"
    /// Stadium air-horn riff for touchdowns.
    case tdHorn = "td_horn"
    /// Crowd roar riser for the big moments.
    case crowdSwell = "crowd_swell"

    /// Per-cue mix level relative to the master volume — the generated
    /// waveforms already sit low; this balances them against each other.
    var gain: Float {
        switch self {
        case .snap:       return 0.7
        case .whistle:    return 0.9
        case .hitLight:   return 0.8
        case .hitBig:     return 0.9
        case .catchPop:   return 0.8
        case .kickThump:  return 0.7
        case .tdHorn:     return 0.8
        case .crowdSwell: return 0.9
        }
    }

    /// Simultaneous voices kept warm per cue. Hits can overlap on gang
    /// tackles; the long one-shot moments never stack.
    var poolSize: Int {
        switch self {
        case .tdHorn, .crowdSwell, .whistle: return 1
        default: return 2
        }
    }
}

// MARK: - AudioDirector

/// Lightweight playback hub for the live 3D match: a preloaded
/// `AVAudioPlayer` pool per cue plus a looping crowd bed whose volume
/// follows the game situation. Triggers come from the choreography
/// (`FootballFieldScene.execute(step:)`) and from `CoachedGameView` at
/// play resolution.
///
/// Design constraints honored here:
/// - `.ambient` session with `.mixWithOthers`: respects the ring/silent
///   switch and never interrupts the user's own music/podcasts.
/// - Zero allocation on the play path: every player is created once in
///   `preload()`; `play(_:)` only picks an idle pooled voice.
/// - "Sound" toggle + volume slider live in Settings (UserDefaults keys
///   `soundEnabled` / `soundVolume`) and are re-read on every trigger so
///   changes apply immediately, including silencing the crowd loop.
final class AudioDirector {

    static let shared = AudioDirector()

    // MARK: State

    private var pools: [MatchSound: [AVAudioPlayer]] = [:]
    private var crowdPlayer: AVAudioPlayer?
    private var loaded = false
    /// True between `startMatch()` and `endMatch()` — the crowd bed should
    /// be audible (subject to the Settings toggle) whenever this holds.
    private var matchActive = false
    /// Last situation-driven crowd intensity (0…1), kept so a Settings
    /// change or foreground return can restore the correct loudness.
    private var crowdIntensity: Double = 0.5

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
            guard let url = Self.assetURL(named: cue.rawValue) else {
                #if DEBUG
                print("AudioDirector: missing asset \(cue.rawValue).wav")
                #endif
                continue
            }
            var voices: [AVAudioPlayer] = []
            for _ in 0..<cue.poolSize {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                voices.append(player)
            }
            pools[cue] = voices
        }
        if let url = Self.assetURL(named: "crowd_loop"),
           let player = try? AVAudioPlayer(contentsOf: url) {
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

    /// Fires a cue from a warm pooled voice. Safe to call from any play
    /// beat — returns silently when sound is off or the asset is missing.
    func play(_ cue: MatchSound) {
        guard soundEnabled else { return }
        if !loaded { preload() }
        guard let pool = pools[cue], !pool.isEmpty else { return }
        let voice = pool.first { !$0.isPlaying } ?? pool[0]
        voice.currentTime = 0
        voice.volume = cue.gain * masterVolume
        voice.play()
    }

    // MARK: Crowd bed

    /// Starts the ambient stadium loop for a live match.
    func startMatch(initialIntensity: Double = 0.5) {
        preload()
        matchActive = true
        crowdIntensity = initialIntensity
        applyCrowdState(fade: 0.8)
    }

    /// Fades the crowd out and releases the field — call when the match
    /// view disappears.
    func endMatch() {
        matchActive = false
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

    /// Reconciles the crowd player with (enabled × active × intensity).
    private func applyCrowdState(fade: TimeInterval) {
        guard let crowd = crowdPlayer else { return }
        guard matchActive, soundEnabled else {
            if crowd.isPlaying { crowd.setVolume(0, fadeDuration: 0.3) }
            return
        }
        if !crowd.isPlaying { crowd.play() }
        // Bed sits well under the SFX: 15 % floor rising to ~60 % of master.
        let target = masterVolume * Float(0.15 + 0.45 * crowdIntensity)
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
