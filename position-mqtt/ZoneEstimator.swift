import Foundation

struct ZoneSighting: Equatable {
    let zone: Zone
    let rssi: Double
    let slant: Double
}

enum ZoneEstimator {
    /// Same path-loss exponent Beacon Position uses. `tx1m` is 1 m.
    static let pathLossN = 3.0
    static let rssiAlpha = 0.32

    static func slantMeters(tx1m: Double, rssi: Double) -> Double {
        pow(10.0, (tx1m - rssi) / (10.0 * pathLossN))
    }

    static func smoothRSSI(previous: Double?, sample: Int, alpha: Double = rssiAlpha) -> Double {
        let value = Double(sample)
        guard let previous else { return value }
        return previous + alpha * (value - previous)
    }

    /// Nearest beacon wins. The current zone stays until another is closer by `hysteresisMeters`.
    static func choose(
        sightings: [ZoneSighting],
        currentZoneID: String?,
        hysteresisMeters: Double
    ) -> ZoneSighting? {
        guard let best = sightings.min(by: { lhs, rhs in
            if lhs.slant != rhs.slant { return lhs.slant < rhs.slant }
            return lhs.zone.id < rhs.zone.id
        }) else { return nil }

        guard
            let currentZoneID,
            let current = sightings.first(where: { $0.zone.id == currentZoneID })
        else { return best }

        if best.zone.id == current.zone.id { return current }
        if best.slant + hysteresisMeters < current.slant { return best }
        return current
    }
}
