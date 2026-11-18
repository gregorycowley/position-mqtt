import Foundation

struct Zone: Equatable, Identifiable {
    let id: String
    let major: Int
    let minor: Int
    let x: Double
    let y: Double
    let tx1m: Double
    let place: String
}

/// CCA RM 140 actual. Four Kontakt beacons, one at the center of each zone.
/// Numbers are the 2026-11-06 inventory in `apps/position/assets/sites/cca-rm140-actual.yaml`.
struct RoomLayout {
    let width: Double
    let height: Double
    let zones: [Zone]

    static let beaconUUID = UUID(uuidString: "F7826DA6-4FA2-4E98-8024-BC5B71E0893E")!

    static let ccaRM140 = RoomLayout(
        width: 7.747,
        height: 11.111,
        zones: [
            Zone(id: "K01", major: 32268, minor: 3719, x: 1.827, y: 4.504, tx1m: -48, place: "left, lower"),
            Zone(id: "K02", major: 11616, minor: 20716, x: 1.827, y: 8.645, tx1m: -44, place: "left, upper"),
            Zone(id: "K03", major: 35436, minor: 14422, x: 5.329, y: 8.645, tx1m: -44, place: "right, upper"),
            Zone(id: "K04", major: 87, minor: 15933, x: 5.329, y: 4.504, tx1m: -40, place: "right, lower"),
        ]
    )

    var splitX: Double {
        let columns = Array(Set(zones.map(\.x))).sorted()
        guard columns.count >= 2 else { return width / 2 }
        return (columns[0] + columns[1]) / 2
    }

    var splitY: Double {
        let rows = Array(Set(zones.map(\.y))).sorted()
        guard rows.count >= 2 else { return height / 2 }
        return (rows[0] + rows[1]) / 2
    }

    func zone(major: Int, minor: Int) -> Zone? {
        zones.first { $0.major == major && $0.minor == minor }
    }
}
