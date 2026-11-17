import Foundation

/// The daily route (experiment `dailyRoute`): one fixed route per UTC calendar date.
///
/// The date alone decides the departure airport, the difficulty, a seed for the obstacle layout
/// of every leg, and the two gates offered at every airport, so everyone who flies it on the
/// same day gets the same flight. Pure and deterministic; normal runs never touch it.
nonisolated struct DailyRoute: Equatable, Hashable, Sendable {
    /// Days since 1970-01-01 (UTC) that this route belongs to.
    let day: Int

    /// Departure airports a daily route can start from (the airport cities).
    static let airports = [0, 3, 5, 8]

    init(day: Int) { self.day = day }

    /// The route for the UTC calendar date that contains `date`.
    init(date: Date) {
        self.day = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The route for today.
    static var today: DailyRoute { DailyRoute(date: .now) }

    // MARK: The day

    var startDate: Date { Date(timeIntervalSince1970: Double(day) * 86_400) }

    /// "2026-11-17": the key the daily best is stored under.
    var key: String {
        let c = Self.utc.dateComponents([.year, .month, .day], from: startDate)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                 "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// "17 NOV".
    var shortDate: String {
        let c = Self.utc.dateComponents([.month, .day], from: startDate)
        return "\(c.day ?? 1) \(Self.months[((c.month ?? 1) - 1) % 12])"
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    // MARK: The route

    /// Route index of the departure airport.
    var startRoute: Int {
        Self.airports[Int(Self.mix(day, salt: 1) % UInt64(Self.airports.count))]
    }

    /// Always Standard, so the daily score means the same thing for everyone.
    var difficultyID: DifficultyID { .standard }
    var difficulty: Difficulty { Difficulty.get(difficultyID) }

    var origin: City { Route.city(startRoute) }
    var destination: City { Route.city(startRoute + 1) }

    // MARK: Seeds and gates

    /// Seed for the obstacle layout of leg `leg` (0 = the first leg of the run).
    func legSeed(_ leg: Int) -> UInt64 {
        Self.mix(day, salt: 100 &+ UInt64(max(leg, 0))) | 1
    }

    /// Seed for the scenery of leg `leg` (it only picks what the skyline looks like).
    func sceneSeed(_ leg: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: Self.mix(day, salt: 500 &+ UInt64(max(leg, 0))))
    }

    /// The two gates at the airport reached after `leg` legs (1 = after the first leg).
    func gateOffer(afterLeg leg: Int, allowSecondChances: Bool) -> GateOffer {
        var rng = SplitMix64(seed: Self.mix(day, salt: 900 &+ UInt64(max(leg, 0))))
        return GateOffer.make(allowSecondChances: allowSecondChances, using: &rng)
    }

    private static func mix(_ day: Int, salt: UInt64) -> UInt64 {
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: day) &* 0x1000_0000_01B3 &+ salt)
        _ = rng.next()
        return rng.next()
    }
}

/// The best score on each daily route, kept on the device by date.
final class DailyBestStore {
    static let shared = DailyBestStore()

    private let defaults: UserDefaults
    private static let key = "skyfold.dailyBest.v1"
    /// Days kept. Older bests are dropped when a new one is written, so the table stays small.
    static let keepDays = 30

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var table: [String: Int] {
        get { (defaults.dictionary(forKey: Self.key) as? [String: Int]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    /// The best score on that day's route, or nil if it has not been flown.
    func best(for route: DailyRoute) -> Int? { table[route.key] }

    /// Records a finished daily run. Returns true when it is the day's best so far.
    @discardableResult
    func record(score: Int, for route: DailyRoute) -> Bool {
        guard score > 0 else { return false } // a run that scored nothing is not a best
        var all = table
        if let old = all[route.key], old >= score { return false }
        all[route.key] = score
        table = Self.pruned(all)
        return true
    }

    /// Keeps the `keepDays` most recent dates (keys sort by date).
    static func pruned(_ all: [String: Int]) -> [String: Int] {
        guard all.count > keepDays else { return all }
        let keep = Set(all.keys.sorted().suffix(keepDays))
        return all.filter { keep.contains($0.key) }
    }

    /// "Reset progress": forgets every daily best.
    func clear() { defaults.removeObject(forKey: Self.key) }
}
