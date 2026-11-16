import Foundation

// MARK: - Sound

/// One-shot sound effects. The audio engine synthesizes all of these procedurally,
/// so the app ships no audio files.
enum SoundEffect: String, CaseIterable, Sendable {
    case laneSwitch      // soft paper "whoosh" when changing altitude
    case star            // bright chime when collecting a lucky star
    case crash           // crumple + thud when hitting an obstacle
    case shieldBreak     // glassy pop when a Paper Shield absorbs a hit
    case countdown       // short tick for 3-2-1
    case takeoff         // rising swell when a leg begins
    case landing         // descending glide + bell when arriving in a city
    case gateOpen        // heavy door creak / slide at the airport
    case blessing        // warm major arpeggio
    case curse           // dissonant low swell
    case unlock          // celebratory sparkle for a new skin/airport/difficulty
    case uiTap           // tiny click for buttons
}

/// Background music moods. `nil` passed to `setMusic` means silence.
enum MusicMood: String, CaseIterable, Sendable {
    case menuDay, menuNight
    case flightDay, flightNight
    case airport
}

@MainActor
protocol SoundService: AnyObject {
    func play(_ effect: SoundEffect)
    /// Crossfades to the given mood (or fades out when nil).
    func setMusic(_ mood: MusicMood?)
    /// 0...1 linear volumes, applied immediately.
    func setVolumes(music: Float, effects: Float)
}

// MARK: - Haptics

enum HapticEvent: Sendable {
    case laneSwitch, star, crash, shield, gate, success, warning, selection
}

@MainActor
protocol HapticService: AnyObject {
    var isEnabled: Bool { get set }
    func play(_ event: HapticEvent)
}

// MARK: - Registry

/// Global access point for side-effect services. Defaults are silent so every
/// module compiles and runs without the real implementations; `SkyfoldApp`
/// installs the real ones at launch.
@MainActor
enum Services {
    static var sound: any SoundService = SilentSoundService()
    static var haptics: any HapticService = SilentHapticService()
}

final class SilentSoundService: SoundService {
    func play(_ effect: SoundEffect) {}
    func setMusic(_ mood: MusicMood?) {}
    func setVolumes(music: Float, effects: Float) {}
}

final class SilentHapticService: HapticService {
    var isEnabled = true
    func play(_ event: HapticEvent) {}
}
