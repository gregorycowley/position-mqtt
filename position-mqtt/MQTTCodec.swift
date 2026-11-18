import Foundation

enum MQTTIncoming: Equatable {
    case connack(UInt8)
    case publish(topic: String, payload: Data)
    case suback
    case pingresp
    case other(UInt8)
}

enum MQTTCodec {
    static func connect(clientID: String, keepAlive: UInt16, willTopic: String, willMessage: String) -> Data {
        // Clean session, will flag, will retain. QoS 0.
        let flags: UInt8 = 0x26
        var header = Data()
        header.appendMQTTString("MQTT")
        header.append(0x04)
        header.append(flags)
        header.appendUInt16(keepAlive)

        var payload = Data()
        payload.appendMQTTString(clientID)
        payload.appendMQTTString(willTopic)
        payload.appendMQTTString(willMessage)
        return packet(type: 0x10, body: header + payload)
    }

    static func subscribe(packetID: UInt16, topics: [String]) -> Data {
        var body = Data()
        body.appendUInt16(packetID)
        for topic in topics {
            body.appendMQTTString(topic)
            body.append(0)
        }
        return packet(type: 0x82, body: body)
    }

    static func publish(topic: String, payload: Data, retain: Bool) -> Data {
        var body = Data()
        body.appendMQTTString(topic)
        body.append(payload)
        return packet(type: retain ? 0x31 : 0x30, body: body)
    }

    static func pingreq() -> Data {
        Data([0xC0, 0x00])
    }

    static func disconnect() -> Data {
        Data([0xE0, 0x00])
    }

    static func takePackets(from buffer: inout Data) -> [MQTTIncoming] {
        var packets: [MQTTIncoming] = []
        var offset = 0
        while offset < buffer.count {
            switch readRemainingLength(buffer, start: offset + 1) {
            case .needMore:
                if offset > 0 { buffer.removeFirst(offset) }
                return packets
            case .malformed:
                buffer.removeAll()
                return packets
            case .ready(let consumed, let remaining):
                if remaining > 262_144 {
                    buffer.removeAll()
                    return packets
                }
                let total = 1 + consumed + remaining
                if offset + total > buffer.count {
                    if offset > 0 { buffer.removeFirst(offset) }
                    return packets
                }
                let type = buffer[offset] >> 4
                let flags = buffer[offset] & 0x0F
                let bodyStart = offset + 1 + consumed
                let body = buffer.subdata(in: bodyStart..<(bodyStart + remaining))
                packets.append(interpret(type: type, flags: flags, body: body))
                offset += total
            }
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return packets
    }

    private enum LengthRead {
        case needMore
        case malformed
        case ready(consumed: Int, value: Int)
    }

    private static func readRemainingLength(_ data: Data, start: Int) -> LengthRead {
        var value = 0
        var multiplier = 1
        var consumed = 0
        while consumed < 4 {
            let index = start + consumed
            if index >= data.count { return .needMore }
            let byte = Int(data[index])
            consumed += 1
            value += (byte & 0x7F) * multiplier
            if byte & 0x80 == 0 { return .ready(consumed: consumed, value: value) }
            multiplier *= 128
        }
        return .malformed
    }

    private static func interpret(type: UInt8, flags: UInt8, body: Data) -> MQTTIncoming {
        switch type {
        case 2:
            guard body.count >= 2 else { return .other(type) }
            return .connack(body[1])
        case 3:
            return decodePublish(flags: flags, body: body)
        case 9:
            return .suback
        case 13:
            return .pingresp
        default:
            return .other(type)
        }
    }

    private static func decodePublish(flags: UInt8, body: Data) -> MQTTIncoming {
        guard body.count >= 2 else { return .other(3) }
        let length = (Int(body[0]) << 8) | Int(body[1])
        let topicEnd = 2 + length
        guard length >= 0, topicEnd <= body.count else { return .other(3) }
        let topic = String(data: body.subdata(in: 2..<topicEnd), encoding: .utf8) ?? ""
        var payloadStart = topicEnd
        let qos = (flags >> 1) & 0x03
        if qos > 0 { payloadStart += 2 }
        guard payloadStart <= body.count else { return .other(3) }
        return .publish(topic: topic, payload: body.subdata(in: payloadStart..<body.count))
    }

    private static func packet(type: UInt8, body: Data) -> Data {
        var data = Data([type])
        data.append(remainingLength(body.count))
        data.append(body)
        return data
    }

    private static func remainingLength(_ value: Int) -> Data {
        var remaining = value
        var encoded = Data()
        repeat {
            var digit = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 { digit |= 0x80 }
            encoded.append(digit)
        } while remaining > 0
        return encoded
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0x00FF))
    }

    mutating func appendMQTTString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }
}
