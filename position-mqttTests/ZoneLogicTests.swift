import XCTest
@testable import PositionMQTT

final class ZoneLogicTests: XCTestCase {
    func testSlantAtOneMeter() {
        let slant = ZoneEstimator.slantMeters(tx1m: -48, rssi: -48)
        XCTAssertEqual(slant, 1, accuracy: 0.0001)
    }

    func testDistanceBeatsLouderRawRSSI() {
        let room = RoomLayout.ccaRM140
        let k01 = room.zones[0]
        let k04 = room.zones[3]
        let nearK01 = ZoneSighting(
            zone: k01,
            rssi: -62,
            slant: ZoneEstimator.slantMeters(tx1m: k01.tx1m, rssi: -62)
        )
        let louderK04 = ZoneSighting(
            zone: k04,
            rssi: -55,
            slant: ZoneEstimator.slantMeters(tx1m: k04.tx1m, rssi: -55)
        )
        XCTAssertLessThan(nearK01.slant, louderK04.slant)
        XCTAssertGreaterThan(louderK04.rssi, nearK01.rssi)
        let chosen = ZoneEstimator.choose(
            sightings: [louderK04, nearK01],
            currentZoneID: nil,
            hysteresisMeters: 0
        )
        XCTAssertEqual(chosen?.zone.id, "K01")
    }

    func testHysteresisHoldsTheCurrentZone() {
        let held = ZoneEstimator.choose(
            sightings: [sighting("K01", slant: 2.0), sighting("K02", slant: 1.8)],
            currentZoneID: "K01",
            hysteresisMeters: 0.4
        )
        XCTAssertEqual(held?.zone.id, "K01")

        let switched = ZoneEstimator.choose(
            sightings: [sighting("K01", slant: 2.0), sighting("K02", slant: 1.5)],
            currentZoneID: "K01",
            hysteresisMeters: 0.4
        )
        XCTAssertEqual(switched?.zone.id, "K02")
    }

    func testMissingCurrentZoneSwitchesImmediately() {
        let chosen = ZoneEstimator.choose(
            sightings: [sighting("K03", slant: 3)],
            currentZoneID: "K01",
            hysteresisMeters: 2
        )
        XCTAssertEqual(chosen?.zone.id, "K03")
    }

    func testSmoothRSSI() {
        let smoothed = ZoneEstimator.smoothRSSI(previous: -50, sample: -60)
        XCTAssertEqual(smoothed, -53.2, accuracy: 0.0001)
    }

    func testRoomInventory() {
        let room = RoomLayout.ccaRM140
        XCTAssertEqual(room.zones.map(\.id), ["K01", "K02", "K03", "K04"])
        XCTAssertEqual(room.zone(major: 87, minor: 15933)?.id, "K04")
        XCTAssertEqual(room.zone(major: 32268, minor: 3719)?.x ?? 0, 1.827, accuracy: 0.0001)
        XCTAssertEqual(room.width, 7.747, accuracy: 0.0001)
        XCTAssertEqual(room.height, 11.111, accuracy: 0.0001)
        XCTAssertEqual(RoomLayout.beaconUUID.uuidString, "F7826DA6-4FA2-4E98-8024-BC5B71E0893E")
    }

    private func sighting(_ id: String, slant: Double) -> ZoneSighting {
        ZoneSighting(
            zone: Zone(id: id, major: 1, minor: 1, x: 0, y: 0, tx1m: -50, place: ""),
            rssi: -50,
            slant: slant
        )
    }
}
