import Foundation

/// Converts the time-of-day setting into a "nightness" value: 0 = day, 0.5 = dusk, 1 = night.
nonisolated enum TimeOfDay {
    /// Nightness during a flight.
    /// - Parameter cycleT: legs completed + progress through the current leg (0...1).
    static func flightNightness(mode: TimeOfDayMode, cycleT: Double, forceNight: Bool,
                                date: Date = .now) -> Double {
        if forceNight { return 1 }
        switch mode {
        case .day: return 0
        case .night: return 1
        case .clock: return clockNightness(date)
        case .cycle: return cycleNightness(cycleT)
        }
    }

    /// Nightness for menus (cycle mode follows the clock outside of flights).
    static func menuNightness(mode: TimeOfDayMode, date: Date = .now) -> Double {
        switch mode {
        case .day: 0
        case .night: 1
        case .clock, .cycle: clockNightness(date)
        }
    }

    /// Two legs make one full day: the first leg is day that turns to dusk and night as
    /// you near the city, so you land in the dark; the next leg flies through the night
    /// and you land at dawn.
    static func cycleNightness(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 2)
        switch p {
        case ..<0.72: return 0
        case ..<1.0: return smooth((p - 0.72) / 0.28)
        case ..<1.72: return 1
        default: return 1 - smooth((p - 1.72) / 0.28)
        }
    }

    static func clockNightness(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        switch h {
        case 7..<17.5: return 0
        case 17.5..<20: return smooth((h - 17.5) / 2.5)
        case 5..<7: return 1 - smooth((h - 5) / 2)
        default: return 1
        }
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
