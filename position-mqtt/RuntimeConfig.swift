import Foundation

struct RuntimeConfig: Equatable {
    var interval: Double = 1
    var format: PayloadFormat = .json
    var enabled: Bool = true
    var hysteresis: Double = 0.4

    mutating func clamp() {
        interval = min(30, max(0.2, interval))
        hysteresis = min(5, max(0, hysteresis))
    }
}

struct ConfigMessage {
    var targetMAC: String?
    var invalidTarget = false
    var interval: Double?
    var format: PayloadFormat?
    var unknownFormat: String?
    var enabled: Bool?
    var hysteresis: Double?

    static func parse(_ data: Data) -> ConfigMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var message = ConfigMessage()
        if object["mac"] != nil {
            if let mac = object["mac"] as? String, let normalized = PhoneIdentity.normalize(mac) {
                message.targetMAC = normalized
            } else {
                message.invalidTarget = true
            }
        }
        if let interval = number(object, "interval_s") ?? number(object, "interval") {
            message.interval = min(30, max(0.2, interval))
        }
        if let raw = object["format"] as? String {
            if let format = PayloadFormat(rawValue: raw) {
                message.format = format
            } else {
                message.unknownFormat = raw
            }
        }
        if let enabled = object["enabled"] as? Bool {
            message.enabled = enabled
        }
        if let hysteresis = number(object, "hysteresis_m") ?? number(object, "hysteresis") {
            message.hysteresis = min(5, max(0, hysteresis))
        }
        return message
    }

    private static func number(_ object: [String: Any], _ key: String) -> Double? {
        guard let value = object[key], !(value is Bool), let number = value as? NSNumber else {
            return nil
        }
        return number.doubleValue
    }
}

enum ConfigGate {
    static func apply(
        data: Data,
        topic: String,
        mac: String,
        current: RuntimeConfig
    ) -> (config: RuntimeConfig, note: String) {
        guard let message = ConfigMessage.parse(data) else {
            return (current, "Ignored config: not JSON")
        }
        let isFleet = topic == Topics.fleetConfig
        let isDevice = topic == Topics.deviceConfig(mac)
        guard isFleet || isDevice else {
            return (current, "Ignored config topic")
        }
        if isFleet, message.invalidTarget {
            return (current, "Ignored config: bad mac")
        }
        if isFleet, let target = message.targetMAC, target != mac {
            return (current, "Ignored config for \(target)")
        }

        var next = current
        var notes: [String] = []
        if let interval = message.interval {
            next.interval = interval
            notes.append("interval \(label(interval))s")
        }
        if let format = message.format {
            next.format = format
            notes.append("format \(format.rawValue)")
        }
        if let enabled = message.enabled {
            next.enabled = enabled
            notes.append(enabled ? "broadcast on" : "broadcast off")
        }
        if let hysteresis = message.hysteresis {
            next.hysteresis = hysteresis
            notes.append("hysteresis \(label(hysteresis)) m")
        }
        if let unknown = message.unknownFormat {
            notes.append("unknown format \(unknown)")
        }
        next.clamp()
        if notes.isEmpty {
            return (current, "Config had no settings")
        }
        return (next, notes.joined(separator: ", "))
    }

    private static func label(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
