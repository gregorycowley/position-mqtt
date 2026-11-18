import Combine
import CoreLocation
import Foundation

struct ZoneReading: Identifiable, Equatable {
    let id: String
    let place: String
    let rssi: Double?
    let slant: Double?
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var macDraft: String
    @Published var macError: String?
    @Published private(set) var committedMAC: String?
    @Published private(set) var config: RuntimeConfig
    @Published private(set) var mqttStatus = "Enter this phone’s MAC"
    @Published private(set) var locationStatus = "Location not requested"
    @Published private(set) var configNote = "No config yet"
    @Published private(set) var readings: [ZoneReading]
    @Published private(set) var activeZoneID: String?
    @Published private(set) var activeX: Double?
    @Published private(set) var activeY: Double?
    @Published private(set) var lastPayload = ""

    let room = RoomLayout.ccaRM140

    private let mqtt = MQTTSession()
    private let locationManager = CLLocationManager()
    private var rssiEMA: [String: Double] = [:]
    private var lastPublish = Date.distantPast
    private var started = false
    private var connectionEpoch = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeat: Timer?

    private enum Store {
        static let mac = "positionMqtt.mac"
        static let interval = "positionMqtt.interval"
        static let format = "positionMqtt.format"
        static let enabled = "positionMqtt.enabled"
        static let hysteresis = "positionMqtt.hysteresis"
    }

    override init() {
        let defaults = UserDefaults.standard
        let storedMAC = defaults.string(forKey: Store.mac)
        committedMAC = storedMAC
        macDraft = storedMAC ?? ""
        config = Self.loadConfig()
        readings = RoomLayout.ccaRM140.zones.map {
            ZoneReading(id: $0.id, place: $0.place, rssi: nil, slant: nil)
        }
        super.init()
    }

    var activePlace: String? {
        guard let activeZoneID else { return nil }
        return room.zones.first { $0.id == activeZoneID }?.place
    }

    func start() {
        guard !started else { return }
        if NSClassFromString("XCTestCase") != nil { return }
        started = true
        wireMQTT()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        handleAuthorization(locationManager.authorizationStatus)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishPosition(force: false)
            }
        }
        if committedMAC != nil {
            connectMQTT()
        }
    }

    func commitMAC() {
        guard let mac = PhoneIdentity.normalize(macDraft) else {
            macError = "Use 6 bytes, like AA:BB:CC:DD:EE:FF"
            return
        }
        macError = nil
        macDraft = mac
        guard mac != committedMAC else { return }
        committedMAC = mac
        UserDefaults.standard.set(mac, forKey: Store.mac)
        if started { connectMQTT() }
    }

    func setEnabled(_ enabled: Bool) {
        var next = config
        next.enabled = enabled
        config = next
        persistConfig()
        if enabled { publishPosition(force: true) }
    }

    private func wireMQTT() {
        mqtt.onState = { [weak self] text in
            Task { @MainActor in
                self?.mqttStatus = text
            }
        }
        mqtt.onReady = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let epoch = self.connectionEpoch
                self.publishStatus("online")
                self.publishPosition(force: true)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard self.connectionEpoch == epoch else { return }
                    self.publishStatus("online")
                }
            }
        }
        mqtt.onMessage = { [weak self] topic, payload in
            Task { @MainActor in
                self?.applyConfig(topic: topic, payload: payload)
            }
        }
        mqtt.onLost = { [weak self] in
            Task { @MainActor in
                self?.scheduleReconnect()
            }
        }
    }

    private func connectMQTT() {
        reconnectTask?.cancel()
        connectionEpoch += 1
        guard let mac = committedMAC else {
            mqtt.stop()
            mqttStatus = "Enter this phone’s MAC"
            return
        }
        mqttStatus = "Connecting to \(Broker.host)"
        mqtt.start(
            host: Broker.host,
            port: Broker.port,
            clientID: PhoneIdentity.clientID(for: mac),
            willTopic: Topics.status(mac),
            subscriptions: [Topics.fleetConfig, Topics.deviceConfig(mac)]
        )
    }

    private func scheduleReconnect() {
        guard started, committedMAC != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.connectMQTT() }
        }
    }

    private func applyConfig(topic: String, payload: Data) {
        guard let mac = committedMAC else { return }
        let decision = ConfigGate.apply(data: payload, topic: topic, mac: mac, current: config)
        config = decision.config
        configNote = decision.note
        persistConfig()
        if config.enabled { publishPosition(force: true) }
    }

    func ingest(samples: [(major: Int, minor: Int, rssi: Int)]) {
        var heard = Set<String>()
        for sample in samples where sample.rssi != 0 {
            guard let zone = room.zone(major: sample.major, minor: sample.minor) else { continue }
            heard.insert(zone.id)
            rssiEMA[zone.id] = ZoneEstimator.smoothRSSI(previous: rssiEMA[zone.id], sample: sample.rssi)
        }
        for id in Array(rssiEMA.keys) where !heard.contains(id) {
            rssiEMA[id] = nil
        }

        let sightings: [ZoneSighting] = room.zones.compactMap { zone in
            guard let rssi = rssiEMA[zone.id] else { return nil }
            return ZoneSighting(
                zone: zone,
                rssi: rssi,
                slant: ZoneEstimator.slantMeters(tx1m: zone.tx1m, rssi: rssi)
            )
        }
        let chosen = ZoneEstimator.choose(
            sightings: sightings,
            currentZoneID: activeZoneID,
            hysteresisMeters: config.hysteresis
        )
        let changed = chosen?.zone.id != activeZoneID
        activeZoneID = chosen?.zone.id
        activeX = chosen?.zone.x
        activeY = chosen?.zone.y
        readings = room.zones.map { zone in
            let sighting = sightings.first { $0.zone.id == zone.id }
            return ZoneReading(id: zone.id, place: zone.place, rssi: sighting?.rssi, slant: sighting?.slant)
        }
        if chosen == nil {
            return
        }
        publishPosition(force: changed)
    }

    private func publishPosition(force: Bool) {
        guard
            config.enabled,
            let mac = committedMAC,
            let region = activeZoneID,
            let x = activeX,
            let y = activeY
        else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastPublish) < config.interval { return }
        let body = PositionPayload.make(mac: mac, x: x, y: y, region: region, format: config.format)
        lastPayload = body
        lastPublish = now
        mqtt.publish(topic: Topics.position(mac), payload: Data(body.utf8), retain: false)
    }

    private func publishStatus(_ text: String) {
        guard let mac = committedMAC else { return }
        mqtt.publish(topic: Topics.status(mac), payload: Data(text.utf8), retain: true)
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard CLLocationManager.isRangingAvailable() else {
                locationStatus = "Ranging needs a physical iPhone"
                return
            }
            locationStatus = "Ranging"
            locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: RoomLayout.beaconUUID))
        case .denied, .restricted:
            locationStatus = "Location denied"
        case .notDetermined:
            locationStatus = "Asking for location"
        @unknown default:
            locationStatus = "Location unavailable"
        }
    }

    private static func loadConfig() -> RuntimeConfig {
        let defaults = UserDefaults.standard
        var config = RuntimeConfig()
        if defaults.object(forKey: Store.interval) != nil {
            config.interval = defaults.double(forKey: Store.interval)
        }
        if let raw = defaults.string(forKey: Store.format), let format = PayloadFormat(rawValue: raw) {
            config.format = format
        }
        if defaults.object(forKey: Store.enabled) != nil {
            config.enabled = defaults.bool(forKey: Store.enabled)
        }
        if defaults.object(forKey: Store.hysteresis) != nil {
            config.hysteresis = defaults.double(forKey: Store.hysteresis)
        }
        config.clamp()
        return config
    }

    private func persistConfig() {
        let defaults = UserDefaults.standard
        defaults.set(config.interval, forKey: Store.interval)
        defaults.set(config.format.rawValue, forKey: Store.format)
        defaults.set(config.enabled, forKey: Store.enabled)
        defaults.set(config.hysteresis, forKey: Store.hysteresis)
    }
}

extension AppModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorization(status)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying beaconConstraint: CLBeaconIdentityConstraint
    ) {
        let samples = beacons.map { (major: $0.major.intValue, minor: $0.minor.intValue, rssi: $0.rssi) }
        Task { @MainActor in
            self.ingest(samples: samples)
        }
    }
}
