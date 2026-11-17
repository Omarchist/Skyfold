import Foundation
import Observation

nonisolated enum GraphicsQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Fewest background props, no anti-aliasing. For older phones / battery saving.
    case low
    case balanced
    /// Most background props and decorative clouds, anti-aliasing on.
    case high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum ShadowMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    /// A flat dark blob on the ground under each object (cheapest).
    case flat
    /// One shadow-casting directional light.
    case realtime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .flat: "Simple"
        case .realtime: "Real-time"
        }
    }
}

nonisolated enum TimeOfDayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// In flight, day turns to night and back as you fly between cities. Menus follow the clock.
    case cycle
    /// Follow the device clock everywhere.
    case clock
    case day
    case night
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cycle: "Day and night"
        case .clock: "Match my clock"
        case .day: "Always day"
        case .night: "Always night"
        }
    }
}

nonisolated enum ControlScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Swipe up/down to change altitude.
    case swipe
    /// Tap the top/bottom half of the screen.
    case tapZones
    var id: String { rawValue }
    var title: String {
        switch self {
        case .swipe: "Swipe"
        case .tapZones: "Tap top / bottom"
        }
    }
}

/// Player settings and loadout, persisted to UserDefaults on every change.
@Observable
final class GameSettings {
    // Audio & feel
    var musicVolume: Double = 0.6 { didSet { changed(audio: true) } }
    var effectsVolume: Double = 0.8 { didSet { changed(audio: true) } }
    var hapticsEnabled: Bool = true { didSet { changed(audio: true) } }

    // Graphics
    var graphicsQuality: GraphicsQuality = .balanced { didSet { changed() } }
    var shadowMode: ShadowMode = .flat { didSet { changed() } }
    /// Speed lines and the paper trail behind the plane.
    var trailEffects: Bool = true { didSet { changed() } }
    var showFPS: Bool = false { didSet { changed() } }

    // Gameplay
    var timeOfDay: TimeOfDayMode = .cycle { didSet { changed() } }
    var controlScheme: ControlScheme = .swipe { didSet { changed() } }
    var showHints: Bool = true { didSet { changed() } }

    // Loadout (what the next run uses)
    var selectedDifficulty: DifficultyID = .standard { didSet { changed() } }
    var selectedSkin: SkinID = .classic { didSet { changed() } }
    /// Route index of the departure airport.
    var selectedAirport: Int = 0 { didSet { changed() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = false
    private static let key = "skyfold.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Pushes volume/haptics into the installed services. Call once after installing them.
    func applyToServices() {
        Services.sound.setVolumes(music: Float(musicVolume), effects: Float(effectsVolume))
        Services.haptics.isEnabled = hapticsEnabled
    }

    func resetToDefaults() {
        let fresh = Snapshot()
        isLoading = true
        apply(fresh)
        isLoading = false
        save()
        applyToServices()
    }

    // MARK: Persistence

    private func changed(audio: Bool = false) {
        guard !isLoading else { return }
        save()
        if audio { applyToServices() }
    }

    nonisolated struct Snapshot: Codable {
        var musicVolume: Double?
        var effectsVolume: Double?
        var hapticsEnabled: Bool?
        var graphicsQuality: GraphicsQuality?
        var shadowMode: ShadowMode?
        var trailEffects: Bool?
        var showFPS: Bool?
        var timeOfDay: TimeOfDayMode?
        var controlScheme: ControlScheme?
        var showHints: Bool?
        var selectedDifficulty: DifficultyID?
        var selectedSkin: SkinID?
        var selectedAirport: Int?

        enum CodingKeys: String, CodingKey {
            case musicVolume, effectsVolume, hapticsEnabled, graphicsQuality, shadowMode, trailEffects
            case showFPS, timeOfDay, controlScheme, showHints, selectedDifficulty, selectedSkin, selectedAirport
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isLoading = true
        apply(snap)
        isLoading = false
    }

    private func apply(_ s: Snapshot) {
        musicVolume = Self.unit(s.musicVolume, 0.6)
        effectsVolume = Self.unit(s.effectsVolume, 0.8)
        hapticsEnabled = s.hapticsEnabled ?? true
        graphicsQuality = s.graphicsQuality ?? .balanced
        shadowMode = s.shadowMode ?? .flat
        trailEffects = s.trailEffects ?? true
        showFPS = s.showFPS ?? false
        timeOfDay = s.timeOfDay ?? .cycle
        controlScheme = s.controlScheme ?? .swipe
        showHints = s.showHints ?? true
        selectedDifficulty = s.selectedDifficulty ?? .standard
        selectedSkin = s.selectedSkin ?? .classic
        selectedAirport = min(max(s.selectedAirport ?? 0, 0), Route.count - 1)
    }

    private static func unit(_ v: Double?, _ fallback: Double) -> Double {
        guard let v, v.isFinite else { return fallback }
        return min(max(v, 0), 1)
    }

    private func save() {
        let snap = Snapshot(
            musicVolume: musicVolume, effectsVolume: effectsVolume, hapticsEnabled: hapticsEnabled,
            graphicsQuality: graphicsQuality, shadowMode: shadowMode, trailEffects: trailEffects,
            showFPS: showFPS, timeOfDay: timeOfDay, controlScheme: controlScheme, showHints: showHints,
            selectedDifficulty: selectedDifficulty, selectedSkin: selectedSkin, selectedAirport: selectedAirport)
        if let data = try? JSONEncoder().encode(snap) { defaults.set(data, forKey: Self.key) }
    }
}

extension GameSettings.Snapshot {
    /// A value that is missing or unreadable (a removed option, a wrong type) falls back to its
    /// default on its own instead of resetting every setting.
    nonisolated init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        musicVolume = try? c.decodeIfPresent(Double.self, forKey: .musicVolume)
        effectsVolume = try? c.decodeIfPresent(Double.self, forKey: .effectsVolume)
        hapticsEnabled = try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)
        graphicsQuality = try? c.decodeIfPresent(GraphicsQuality.self, forKey: .graphicsQuality)
        shadowMode = try? c.decodeIfPresent(ShadowMode.self, forKey: .shadowMode)
        trailEffects = try? c.decodeIfPresent(Bool.self, forKey: .trailEffects)
        showFPS = try? c.decodeIfPresent(Bool.self, forKey: .showFPS)
        timeOfDay = try? c.decodeIfPresent(TimeOfDayMode.self, forKey: .timeOfDay)
        controlScheme = try? c.decodeIfPresent(ControlScheme.self, forKey: .controlScheme)
        showHints = try? c.decodeIfPresent(Bool.self, forKey: .showHints)
        selectedDifficulty = try? c.decodeIfPresent(DifficultyID.self, forKey: .selectedDifficulty)
        selectedSkin = try? c.decodeIfPresent(SkinID.self, forKey: .selectedSkin)
        selectedAirport = try? c.decodeIfPresent(Int.self, forKey: .selectedAirport)
    }
}
