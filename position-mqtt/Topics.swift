import Foundation

enum Broker {
    static let host = "pi02zigbee.lan"
    static let port: UInt16 = 1883
    /// Leading slash is part of the prefix. `cca/r140/...` is a different tree.
    static let topicPrefix = "/cca/r140/iphone/"
}

enum Topics {
    static func position(_ mac: String) -> String {
        Broker.topicPrefix + mac + "/position"
    }

    static func status(_ mac: String) -> String {
        Broker.topicPrefix + mac + "/status"
    }

    static func deviceConfig(_ mac: String) -> String {
        Broker.topicPrefix + mac + "/config"
    }

    static var fleetConfig: String {
        Broker.topicPrefix + "config"
    }
}
