import XCTest
@testable import PositionMQTT

final class MessageTests: XCTestCase {
    func testMACNormalize() {
        XCTAssertEqual(PhoneIdentity.normalize("aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(PhoneIdentity.normalize("aa-bb-cc-dd-ee-ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(PhoneIdentity.normalize("aabbccddeeff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(PhoneIdentity.normalize("not a mac"))
        XCTAssertNil(PhoneIdentity.normalize("AA:BB:CC:DD:EE"))
        XCTAssertEqual(PhoneIdentity.clientID(for: "AA:BB:CC:DD:EE:FF"), "iphone-AABBCCDDEEFF")
    }

    func testTopicsUseThePrefix() {
        let mac = "AA:BB:CC:DD:EE:FF"
        XCTAssertEqual(Topics.position(mac), "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/position")
        XCTAssertEqual(Topics.status(mac), "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/status")
        XCTAssertEqual(Topics.deviceConfig(mac), "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/config")
        XCTAssertEqual(Topics.fleetConfig, "/cca/r140/iphone/config")
        XCTAssertEqual(Broker.host, "pi02zigbee.lan")
        XCTAssertEqual(Broker.port, 1883)
    }

    func testPayloadFormats() {
        let mac = "AA:BB:CC:DD:EE:FF"
        XCTAssertEqual(
            PositionPayload.make(mac: mac, x: 1.827, y: 4.504, region: "K01", format: .json),
            #"{"mac":"AA:BB:CC:DD:EE:FF","x":1.827,"y":4.504,"region":"K01"}"#
        )
        XCTAssertEqual(
            PositionPayload.make(mac: mac, x: 1.827, y: 4.504, region: "K01", format: .xy),
            "1.827,4.504"
        )
        XCTAssertEqual(
            PositionPayload.make(mac: mac, x: 1.827, y: 4.504, region: "K01", format: .region),
            "K01"
        )
        XCTAssertEqual(
            PositionPayload.make(mac: mac, x: 1.827, y: 4.504, region: "K01", format: .xyRegion),
            "1.827,4.504,K01"
        )
    }

    func testFleetConfigTargetsOnePhone() {
        let mac = "AA:BB:CC:DD:EE:FF"
        let other = Data(#"{"mac":"11:22:33:44:55:66","format":"region"}"#.utf8)
        let ignored = ConfigGate.apply(data: other, topic: Topics.fleetConfig, mac: mac, current: RuntimeConfig())
        XCTAssertEqual(ignored.config.format, .json)
        XCTAssertTrue(ignored.note.contains("11:22:33:44:55:66"))

        let mine = Data(#"{"mac":"aa:bb:cc:dd:ee:ff","interval_s":2,"enabled":false}"#.utf8)
        let applied = ConfigGate.apply(data: mine, topic: Topics.fleetConfig, mac: mac, current: RuntimeConfig())
        XCTAssertEqual(applied.config.interval, 2)
        XCTAssertFalse(applied.config.enabled)

        let broadcast = Data(#"{"format":"xy_region","hysteresis_m":0.8}"#.utf8)
        let all = ConfigGate.apply(data: broadcast, topic: Topics.fleetConfig, mac: mac, current: RuntimeConfig())
        XCTAssertEqual(all.config.format, .xyRegion)
        XCTAssertEqual(all.config.hysteresis, 0.8, accuracy: 0.0001)
    }

    func testDeviceConfigAndRejects() {
        let mac = "AA:BB:CC:DD:EE:FF"
        let data = Data(#"{"format":"region"}"#.utf8)
        let applied = ConfigGate.apply(data: data, topic: Topics.deviceConfig(mac), mac: mac, current: RuntimeConfig())
        XCTAssertEqual(applied.config.format, .region)

        let junk = Data("nope".utf8)
        let ignored = ConfigGate.apply(data: junk, topic: Topics.fleetConfig, mac: mac, current: RuntimeConfig())
        XCTAssertEqual(ignored.note, "Ignored config: not JSON")

        let badMAC = Data(#"{"mac":"phone-1","enabled":false}"#.utf8)
        let rejected = ConfigGate.apply(data: badMAC, topic: Topics.fleetConfig, mac: mac, current: RuntimeConfig())
        XCTAssertTrue(rejected.config.enabled)
        XCTAssertEqual(rejected.note, "Ignored config: bad mac")

        let fast = Data(#"{"interval_s":0.01}"#.utf8)
        let clamped = ConfigGate.apply(data: fast, topic: Topics.deviceConfig(mac), mac: mac, current: RuntimeConfig())
        XCTAssertEqual(clamped.config.interval, 0.2, accuracy: 0.0001)
    }
}
