import Foundation

nonisolated enum ModifierKind: String, Codable, Sendable {
    case blessing, curse
}

/// Curses and blessings handed out at airport gates. They last for the rest of the run
/// and stack when you pick the same one again.
nonisolated enum ModifierID: String, CaseIterable, Codable, Identifiable, Sendable {
    // Blessings
    case tailwind, paperShield, calmAir, clearSkies, secondWind, luckyDraw, nimbleCrease, shortcut
    // Curses
    case headwind, fogBank, stormFront, soggyPaper, longHaul, restlessFlock, mirrorSky, eclipse, leakyPockets

    var id: String { rawValue }
    var info: ModifierInfo { ModifierInfo.get(self) }
    var kind: ModifierKind { info.kind }

    static var blessings: [ModifierID] { allCases.filter { $0.kind == .blessing } }
    static var curses: [ModifierID] { allCases.filter { $0.kind == .curse } }
}

nonisolated struct ModifierInfo: Sendable {
    let id: ModifierID
    let kind: ModifierKind
    let name: String
    /// What it does, in one short line (shown on the gate reveal and in the HUD).
    let effect: String
    /// Journal lore, written as a traveler's note.
    let lore: String
    /// SF Symbol name.
    let symbol: String

    static func get(_ id: ModifierID) -> ModifierInfo { table[id]! }

    private static let table: [ModifierID: ModifierInfo] = Dictionary(uniqueKeysWithValues: [
        ModifierInfo(id: .tailwind, kind: .blessing, name: "Tailwind",
                     effect: "Score ×1.25 for the rest of the run.",
                     lore: "Wind at my back the whole way. Made good time.",
                     symbol: "wind"),
        ModifierInfo(id: .paperShield, kind: .blessing, name: "Paper Shield",
                     effect: "Absorbs one hit.",
                     lore: "Folded an extra sheet over the nose. Should take one knock.",
                     symbol: "shield.lefthalf.filled"),
        ModifierInfo(id: .calmAir, kind: .blessing, name: "Calm Air",
                     effect: "Flight speed −8%.",
                     lore: "Air like glass today. Slowed right down.",
                     symbol: "leaf"),
        ModifierInfo(id: .clearSkies, kind: .blessing, name: "Clear Skies",
                     effect: "15% fewer obstacles.",
                     lore: "Hardly anything up there. Quiet leg.",
                     symbol: "sun.max"),
        ModifierInfo(id: .secondWind, kind: .blessing, name: "Second Wind",
                     effect: "Revive once after a crash.",
                     lore: "Went down hard. Smoothed the creases out and kept going.",
                     symbol: "arrow.counterclockwise.circle"),
        ModifierInfo(id: .luckyDraw, kind: .blessing, name: "Lucky Draw",
                     effect: "Stars in nearby lanes drift to you, and are worth 20% more.",
                     lore: "The stars kept drifting my way. Not complaining.",
                     symbol: "star.circle"),
        ModifierInfo(id: .nimbleCrease, kind: .blessing, name: "Nimble Crease",
                     effect: "Change altitude 25% faster.",
                     lore: "Re-creased the wingtips. Turns a lot quicker now.",
                     symbol: "arrow.up.and.down"),
        ModifierInfo(id: .shortcut, kind: .blessing, name: "Shortcut",
                     effect: "Future legs are 15% shorter.",
                     lore: "Man at the desk knew a shorter route.",
                     symbol: "point.topleft.down.to.point.bottomright.curvepath"),

        ModifierInfo(id: .headwind, kind: .curse, name: "Headwind",
                     effect: "Flight speed +10%.",
                     lore: "Flying into the wind. Everything comes at me faster.",
                     symbol: "tornado"),
        ModifierInfo(id: .fogBank, kind: .curse, name: "Fog Bank",
                     effect: "Thick fog hides what's ahead.",
                     lore: "Couldn't see past my own nose for most of it.",
                     symbol: "cloud.fog"),
        ModifierInfo(id: .stormFront, kind: .curse, name: "Storm Front",
                     effect: "20% more obstacles.",
                     lore: "Weather moved in right after the gate. Busy skies.",
                     symbol: "cloud.bolt.rain"),
        ModifierInfo(id: .soggyPaper, kind: .curse, name: "Soggy Paper",
                     effect: "Change altitude 30% slower.",
                     lore: "Got caught in the rain. Wings heavy and slow.",
                     symbol: "drop"),
        ModifierInfo(id: .longHaul, kind: .curse, name: "Long Haul",
                     effect: "Future legs are 20% longer.",
                     lore: "They added a stop. Nobody said why.",
                     symbol: "map"),
        ModifierInfo(id: .restlessFlock, kind: .curse, name: "Restless Flock",
                     effect: "Birds may swerve between lanes.",
                     lore: "The birds out here don't hold a line.",
                     symbol: "bird"),
        ModifierInfo(id: .mirrorSky, kind: .curse, name: "Mirror Sky",
                     effect: "Swipe controls are reversed. Taking it twice cancels it.",
                     lore: "Turned up when I meant down. Twice.",
                     symbol: "arrow.up.arrow.down"),
        ModifierInfo(id: .eclipse, kind: .curse, name: "Eclipse",
                     effect: "Endless night for the rest of the run.",
                     lore: "Sun went out an hour after takeoff and didn't come back.",
                     symbol: "moon.haze"),
        ModifierInfo(id: .leakyPockets, kind: .curse, name: "Leaky Pockets",
                     effect: "Stars are worth half.",
                     lore: "Tear in the fold. Lost half of what I picked up.",
                     symbol: "star.slash"),
    ].map { ($0.id, $0) })
}

/// The combined numeric effect of every modifier collected this run.
/// Every curse also adds +10% score, so risk pays.
nonisolated struct RunTuning: Equatable, Sendable {
    var speed: Float = 1
    var density: Float = 1
    var laneSwitchTime: Float = 1
    var legLength: Double = 1
    var score: Double = 1
    var starValue: Double = 1
    /// Stars in adjacent lanes drift toward the plane.
    var magnet = false
    /// 0 = clear, up to 0.9 = very foggy.
    var fog: Float = 0
    /// Chance (0...1) that a bird changes lanes as it approaches.
    var wanderingBirds: Float = 0
    var invertControls = false
    var forceNight = false

    static func combine(_ modifiers: [ModifierID]) -> RunTuning {
        var t = RunTuning()
        for m in modifiers {
            switch m {
            case .tailwind: t.score *= 1.25
            case .paperShield, .secondWind: break // granted as charges by RunSession
            case .calmAir: t.speed *= 0.92
            case .clearSkies: t.density *= 0.85
            case .luckyDraw: t.magnet = true; t.starValue *= 1.2
            case .nimbleCrease: t.laneSwitchTime *= 0.75
            case .shortcut: t.legLength *= 0.85
            case .headwind: t.speed *= 1.10
            case .fogBank: t.fog = min(0.9, t.fog + 0.45)
            case .stormFront: t.density *= 1.2
            case .soggyPaper: t.laneSwitchTime *= 1.3
            case .longHaul: t.legLength *= 1.2
            case .restlessFlock: t.wanderingBirds = min(0.8, t.wanderingBirds + 0.35)
            case .mirrorSky: t.invertControls.toggle()
            case .eclipse: t.forceNight = true
            case .leakyPockets: t.starValue *= 0.5
            }
            if m.kind == .curse { t.score *= 1.1 }
        }
        return t
    }
}

/// The two doors offered at an airport: one blessing and one curse, in random order.
/// The player doesn't know which is which until a door opens.
nonisolated struct GateOffer: Equatable, Sendable {
    let options: [ModifierID]
    var chosenIndex: Int?

    var chosen: ModifierID? { chosenIndex.map { options[$0] } }

    static func make(allowSecondChances: Bool) -> GateOffer {
        var blessings = ModifierID.blessings
        if !allowSecondChances { blessings.removeAll { $0 == .paperShield || $0 == .secondWind } }
        let blessing = blessings.randomElement()!
        let curse = ModifierID.curses.randomElement()!
        return GateOffer(options: [blessing, curse].shuffled(), chosenIndex: nil)
    }

    /// The same draw from a seeded generator (the daily route), so every player sees the same gates.
    static func make<G: RandomNumberGenerator>(allowSecondChances: Bool, using rng: inout G) -> GateOffer {
        var blessings = ModifierID.blessings
        if !allowSecondChances { blessings.removeAll { $0 == .paperShield || $0 == .secondWind } }
        let blessing = blessings.randomElement(using: &rng)!
        let curse = ModifierID.curses.randomElement(using: &rng)!
        return GateOffer(options: [blessing, curse].shuffled(using: &rng), chosenIndex: nil)
    }
}
