import AVFoundation
import os
#if os(iOS)
import UIKit
#endif

/// Skyfold's sound: every effect and music loop is synthesized at launch (see Synth.swift),
/// so the app ships no audio files.
///
/// Graph:
///
///     6 × AVAudioPlayerNode ─▶ effectsMixer ─┐
///                                            ├─▶ mainMixerNode ─▶ output
///     2 × AVAudioPlayerNode ─▶ musicMixer ───┘
///
/// Effects are pre-rendered into mono buffers on a background task and played round-robin
/// on the effect players. Music loops render in the background (the requested mood first)
/// and loop gaplessly on two players with an equal-power crossfade between moods. Until a
/// buffer is ready, `play` is a no-op and `setMusic` simply remembers the mood.
///
/// Install at launch:
///
///     Services.sound = AudioEngine.shared
///     AudioEngine.shared.start()
///
/// All engine calls happen on the main actor; only the pure, `nonisolated` synthesis runs
/// on background threads. Nothing here installs a render block, so no MainActor state is
/// ever touched from the audio thread.
final class AudioEngine: SoundService {
    static let shared = AudioEngine()

    // MARK: Tuning

    private static let effectVoiceCount = 6
    private static let musicVoiceCount = 2
    private static let crossfadeSeconds: Double = 1.2
    private static let duckSeconds: Double = 0.6
    /// Music sits a little under the effects; the user's music volume scales on top.
    private static let musicTrim: Float = 0.7
    /// After a failed restart, wait this long before trying again from `play`.
    private static let restartBackoff: TimeInterval = 2

    /// When true (default), the soundtrack fades out while another app's audio is playing,
    /// following Apple's `secondaryAudioShouldBeSilencedHint` guidance for games. Effects
    /// still play and mix with the user's audio either way.
    var silencesMusicForOtherAudio = true {
        didSet { runFader() }
    }

    // MARK: State

    private let log = Logger(subsystem: "Skyfold", category: "Audio")
    private let format: AVAudioFormat

    private var engine = AVAudioEngine()
    private var effectsMixer = AVAudioMixerNode()
    private var musicMixer = AVAudioMixerNode()
    private var effectPlayers: [AVAudioPlayerNode] = []
    private var effectBusyUntil: [TimeInterval] = []
    private var nextEffectPlayer = 0
    private var musicVoices: [MusicVoice] = []

    private var effectBuffers: [SoundEffect: [AVAudioPCMBuffer]] = [:]
    private var variantCursor: [SoundEffect: Int] = [:]
    private var musicBuffers: [MusicMood: AVAudioPCMBuffer] = [:]
    private var musicInFlight: Set<MusicMood> = []

    private var desiredMood: MusicMood?
    private var musicVolume: Float = 0.8
    private var effectsVolume: Float = 1
    private var duckLevel: Float = 1
    private var otherAudioPlaying = false

    private var started = false
    private var lastRestartAttempt: TimeInterval = -.infinity
    private var fadeTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private final class MusicVoice {
        let player: AVAudioPlayerNode
        var mood: MusicMood?
        /// Fade position 0...1; the player's volume is sin(level·π/2) (equal power).
        var level: Float = 0
        var target: Float = 0

        init(player: AVAudioPlayerNode) { self.player = player }
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: DSP.sampleRate, channels: 1)!
    }

    // MARK: SoundService

    /// Configures the audio session, starts the engine and starts rendering every buffer
    /// in the background. Idempotent; `play` and `setMusic` call it lazily as well.
    func start() {
        guard !started else { return }
        started = true
        configureSession()
        buildGraph()
        restart()
        installObservers()
        renderEffects()
    }

    func play(_ effect: SoundEffect) {
        start()
        guard let variants = effectBuffers[effect], !variants.isEmpty, ensureRunning() else { return }
        let cursor = variantCursor[effect, default: 0]
        variantCursor[effect] = cursor &+ 1
        let buffer = variants[cursor % variants.count]

        let now = ProcessInfo.processInfo.systemUptime
        let index = pickEffectPlayer(now: now)
        let player = effectPlayers[index]
        // `.interrupts` only matters when all voices are busy and the oldest one is stolen.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        effectBusyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
    }

    func setMusic(_ mood: MusicMood?) {
        start()
        desiredMood = mood
        if let mood, musicBuffers[mood] == nil {
            // Keep the current loop playing; installMusic crossfades once this one is ready.
            renderMusic(mood, priority: .userInitiated)
        } else {
            crossfade(to: mood)
        }
    }

    func setVolumes(music: Float, effects: Float) {
        musicVolume = Self.unit(music)
        effectsVolume = Self.unit(effects)
        musicMixer.outputVolume = musicVolume
        effectsMixer.outputVolume = effectsVolume
    }

    // MARK: Graph and engine lifecycle

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .ambient mixes with the user's audio and respects the silent switch.
            try session.setCategory(.ambient, mode: .default, options: [])
            try? session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            log.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
        otherAudioPlaying = session.secondaryAudioShouldBeSilencedHint
        #endif
    }

    private func buildGraph() {
        engine.attach(effectsMixer)
        engine.attach(musicMixer)
        engine.connect(effectsMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: nil)

        effectPlayers = (0..<Self.effectVoiceCount).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: effectsMixer, format: format)
            return player
        }
        effectBusyUntil = Array(repeating: 0, count: effectPlayers.count)
        nextEffectPlayer = 0

        musicVoices = (0..<Self.musicVoiceCount).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: musicMixer, format: format)
            player.volume = 0
            return MusicVoice(player: player)
        }

        effectsMixer.outputVolume = effectsVolume
        musicMixer.outputVolume = musicVolume
        engine.prepare()
    }

    /// (Re)starts the engine and resets the players. Logs and returns false on failure;
    /// the game then stays silent rather than crashing.
    @discardableResult
    private func restart() -> Bool {
        lastRestartAttempt = ProcessInfo.processInfo.systemUptime
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                log.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        for player in effectPlayers {
            player.stop()
            player.play()
        }
        effectBusyUntil = Array(repeating: 0, count: effectPlayers.count)
        // Restart the wanted loop from the top with a fade-in.
        for voice in musicVoices {
            voice.player.stop()
            voice.player.volume = 0
            voice.mood = nil
            voice.level = 0
            voice.target = 0
        }
        if let mood = desiredMood, musicBuffers[mood] != nil { crossfade(to: mood) }
        return true
    }

    /// True if the engine is running, trying a (rate-limited) restart if it is not.
    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRestartAttempt > Self.restartBackoff else { return false }
        return restart()
    }

    // MARK: Notifications

    private func installObservers() {
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                // .began: the system already stopped the engine. .ended: bring it back.
                if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended {
                    self?.restart()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAfterMediaServicesReset() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let type = raw.flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init(rawValue:))
                else { return }
                self.otherAudioPlaying = type == .begin
                self.runFader()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.started else { return }
                self.otherAudioPlaying = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
                self.runFader()
                if !self.engine.isRunning { self.restart() }
            }
        })
        #endif
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: nil, queue: .main) { [weak self] note in
            let sender = note.object.map { ObjectIdentifier($0 as AnyObject) }
            MainActor.assumeIsolated {
                // The engine stops itself when the output hardware changes (route, rate).
                guard let self, sender == ObjectIdentifier(self.engine), !self.engine.isRunning else { return }
                self.restart()
            }
        })
    }

    /// After a media-services reset every AVAudio object is dead: build a fresh engine.
    /// The PCM buffers are plain memory and are reused.
    private func rebuildAfterMediaServicesReset() {
        log.notice("Media services were reset; rebuilding the audio engine")
        engine = AVAudioEngine()
        effectsMixer = AVAudioMixerNode()
        musicMixer = AVAudioMixerNode()
        configureSession()
        buildGraph()
        restart()
    }

    // MARK: Effects

    private func renderEffects() {
        Task.detached(priority: .userInitiated) { [weak self] in
            var rendered: [SoundEffect: [[Float]]] = [:]
            for effect in SoundEffect.allCases {
                rendered[effect] = (0..<SoundSynth.variantCount(effect)).map {
                    SoundSynth.render(effect, variant: $0)
                }
            }
            await self?.installEffects(rendered)
        }
    }

    private func installEffects(_ rendered: [SoundEffect: [[Float]]]) {
        for (effect, variants) in rendered {
            effectBuffers[effect] = variants.compactMap { makeBuffer($0) }
        }
        prewarmNextMusic()
    }

    /// Prefers an idle player (starting after the last one used); if all six are busy,
    /// steals the one that will finish soonest.
    private func pickEffectPlayer(now: TimeInterval) -> Int {
        let count = effectPlayers.count
        for offset in 0..<count {
            let i = (nextEffectPlayer + offset) % count
            if effectBusyUntil[i] <= now {
                nextEffectPlayer = (i + 1) % count
                return i
            }
        }
        var best = 0
        for i in 1..<count where effectBusyUntil[i] < effectBusyUntil[best] { best = i }
        return best
    }

    // MARK: Music

    private func renderMusic(_ mood: MusicMood, priority: TaskPriority, thenPrewarm: Bool = false) {
        guard musicBuffers[mood] == nil, !musicInFlight.contains(mood) else {
            if thenPrewarm { prewarmNextMusic() }
            return
        }
        musicInFlight.insert(mood)
        Task.detached(priority: priority) { [weak self] in
            let samples = MusicSynth.render(mood)
            await self?.installMusic(mood, samples: samples, thenPrewarm: thenPrewarm)
        }
    }

    private func installMusic(_ mood: MusicMood, samples: [Float], thenPrewarm: Bool) {
        musicInFlight.remove(mood)
        guard let buffer = makeBuffer(samples) else {
            log.error("Could not allocate the \(mood.rawValue, privacy: .public) music buffer")
            return
        }
        musicBuffers[mood] = buffer
        if desiredMood == mood { crossfade(to: mood) }
        if thenPrewarm { prewarmNextMusic() }
    }

    /// Renders the remaining moods one at a time at utility priority, wanted mood first.
    private func prewarmNextMusic() {
        let pending = MusicMood.allCases.filter { musicBuffers[$0] == nil && !musicInFlight.contains($0) }
        let wanted = desiredMood.flatMap { pending.contains($0) ? $0 : nil }
        guard let next = wanted ?? pending.first else { return }
        renderMusic(next, priority: .utility, thenPrewarm: true)
    }

    /// Fades `mood` in on a music voice and every other voice out (or all out for nil).
    private func crossfade(to mood: MusicMood?) {
        guard engine.isRunning, !musicVoices.isEmpty else { return }   // restart() resumes it
        var incoming: MusicVoice?
        if let mood {
            guard let buffer = musicBuffers[mood] else { return }
            if let current = musicVoices.first(where: { $0.mood == mood }) {
                incoming = current                       // already playing (maybe fading out)
            } else {
                // Keep the fade in progress if both voices are audible. Once one goes
                // quiet, stepFades starts the latest requested mood if its buffer is ready.
                guard let free = musicVoices.first(where: { $0.level == 0 }) else { return }
                free.player.stop()
                free.player.volume = 0
                free.player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                free.player.play()
                free.mood = mood
                incoming = free
            }
        }
        for voice in musicVoices { voice.target = voice === incoming ? 1 : 0 }
        runFader()
    }

    private func runFader() {
        guard fadeTask == nil else { return }
        fadeTask = Task { [weak self] in
            var last = ContinuousClock.now
            while true {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = (now - last) / .seconds(1)
                last = now
                guard let self else { return }
                if !self.stepFades(dt: dt) {
                    self.fadeTask = nil
                    return
                }
            }
        }
    }

    /// Advances the crossfade and the other-audio duck; false once everything has settled.
    private func stepFades(dt: Double) -> Bool {
        let duckTarget: Float = silencesMusicForOtherAudio && otherAudioPlaying ? 0 : 1
        duckLevel = Self.approach(duckLevel, duckTarget, by: Float(dt / Self.duckSeconds))
        var moving = duckLevel != duckTarget
        var freedVoice = false
        let step = Float(dt / Self.crossfadeSeconds)
        for voice in musicVoices {
            voice.level = Self.approach(voice.level, voice.target, by: step)
            if voice.level != voice.target { moving = true }
            voice.player.volume = Self.musicTrim * duckLevel * sin(voice.level * .pi / 2)
            if voice.level == 0, voice.target == 0, voice.mood != nil {
                voice.player.stop()
                voice.mood = nil
                freedVoice = true
            }
        }
        if freedVoice, let mood = desiredMood, musicBuffers[mood] != nil,
           !musicVoices.contains(where: { $0.mood == mood }) {
            crossfade(to: mood)
            return true
        }
        return moving
    }

    // MARK: Helpers

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let count = AVAudioFrameCount(samples.count)
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = count
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private static func approach(_ value: Float, _ target: Float, by step: Float) -> Float {
        value < target ? min(target, value + step) : max(target, value - step)
    }

    private static func unit(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }
}
