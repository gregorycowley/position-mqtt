import XCTest
@testable import PositionMQTT

final class MQTTCodecTests: XCTestCase {
    func testConnectCarriesWill() {
        let packet = MQTTCodec.connect(
            clientID: "iphone-AABBCCDDEEFF",
            keepAlive: 30,
            willTopic: "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/status",
            willMessage: "offline"
        )
        XCTAssertEqual(packet[0], 0x10)
        XCTAssertEqual(packet[2], 0x00)
        XCTAssertEqual(packet[3], 0x04)
        XCTAssertEqual(String(data: packet.subdata(in: 4..<8), encoding: .utf8), "MQTT")
        XCTAssertEqual(packet[8], 0x04)
        XCTAssertEqual(packet[9], 0x26)
        XCTAssertEqual(packet[10], 0x00)
        XCTAssertEqual(packet[11], 30)
        XCTAssertTrue(packet.contains(contentsOf: Array("iphone-AABBCCDDEEFF".utf8)))
        XCTAssertTrue(packet.contains(contentsOf: Array("offline".utf8)))
    }

    func testPublishRoundTrip() {
        let payload = Data(#"{"region":"K01"}"#.utf8)
        let packet = MQTTCodec.publish(topic: "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/position", payload: payload, retain: false)
        var buffer = packet
        let packets = MQTTCodec.takePackets(from: &buffer)
        XCTAssertEqual(packets, [.publish(topic: "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/position", payload: payload)])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTwoPacketsAndAPartial() {
        let first = MQTTCodec.publish(topic: "a", payload: Data("one".utf8), retain: true)
        let second = Data([0x20, 0x02, 0x00, 0x00])
        var buffer = first + second + Data([0x30, 0x0A])
        let packets = MQTTCodec.takePackets(from: &buffer)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(packets[0], .publish(topic: "a", payload: Data("one".utf8)))
        XCTAssertEqual(packets[1], .connack(0))
        XCTAssertEqual(buffer, Data([0x30, 0x0A]))
    }

    func testMalformedRemainingLengthDropsTheBuffer() {
        var buffer = Data([0x30, 0xFF, 0xFF, 0xFF, 0xFF])
        let packets = MQTTCodec.takePackets(from: &buffer)
        XCTAssertTrue(packets.isEmpty)
        XCTAssertTrue(buffer.isEmpty)
    }
}

private extension Data {
    func contains(contentsOf bytes: [UInt8]) -> Bool {
        guard bytes.count <= count else { return false }
        for start in 0...(count - bytes.count) {
            if self[startIndex + start..<startIndex + start + bytes.count].elementsEqual(bytes) {
                return true
            }
        }
        return false
    }
}
