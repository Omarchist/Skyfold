import Foundation
import Observation

/// First-landing dates for the postcards. Which postcards exist is derived from `ProgressStore`
/// (visited cities), so "Reset progress" clears them; this store only remembers the date each
/// city was first landed in, and drops dates for cities that are no longer visited.
@Observable
final class PostcardStore {
    static let shared = PostcardStore()

    private(set) var dates: [Int: Date]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "skyfold.postcards.dates.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        var loaded: [Int: Date] = [:]
        for (k, v) in raw { if let i = Int(k) { loaded[i] = Date(timeIntervalSince1970: v) } }
        dates = loaded
    }

    func date(for cityIndex: Int) -> Date? { dates[cityIndex] }

    /// A first landing: always writes, so a card mailed again after a reset gets the new date.
    func recordLanding(_ cityIndex: Int, on date: Date = .now) {
        guard cityIndex != 0 else { return }
        dates[cityIndex] = date
        save()
    }

    /// Dates the visited cities that have none (progress seeded without a landing) and forgets
    /// dates of cities that are not visited any more.
    func reconcile(visited: Set<Int>) {
        var next = dates.filter { visited.contains($0.key) }
        for i in visited where i != 0 && next[i] == nil { next[i] = .now }
        guard next != dates else { return }
        dates = next
        save()
    }

    private func save() {
        var raw: [String: Double] = [:]
        for (i, d) in dates { raw[String(i)] = d.timeIntervalSince1970 }
        defaults.set(raw, forKey: Self.key)
    }
}

/// Short logbook lines for the back of each card.
enum PostcardCopy {
    static func message(for cityIndex: Int) -> String {
        switch cityIndex {
        case 1: "Landed on a flat roof. Saffron on every side. Paper dries fast here."
        case 2: "Headwind off the desert all afternoon. Three triangles, one very large."
        case 3: "Gulls on both sides of the strait. Kept clear of the domes."
        case 4: "Cloud sat on the bay. Landed wet, dry again by the gate."
        case 5: "Quiet air over the temples. Made no sound on the way in."
        case 6: "Storm behind me, harbour ahead. The folds held."
        case 7: "Warm air, easy flying. Very nearly got careless."
        case 8: "Mountain on the left, sea on the right. Nothing in between."
        case 9: "Flew low between the towers. Stayed lucky."
        default: "Landed safely. Wish you were here."
        }
    }
}
