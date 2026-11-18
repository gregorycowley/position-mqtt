import Foundation
import Network

/// MQTT 3.1.1 over TCP. QoS 0 publish and subscribe, with a retained last will.
final class MQTTSession {
    var onState: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onMessage: ((String, Data) -> Void)?
    var onLost: (() -> Void)?

    private let queue = DispatchQueue(label: "position-mqtt.session")
    private var connection: NWConnection?
    private var buffer = Data()
    private var ready = false
    private var subscriptions: [String] = []
    private var pending: [(topic: String, payload: Data, retain: Bool)] = []
    private var pingTimer: DispatchSourceTimer?
    private var generation = 0
    private var stopped = false
    private var reportedLoss = false
    private let keepAlive: UInt16 = 30

    func start(host: String, port: UInt16, clientID: String, willTopic: String, subscriptions: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            let generation = self.generation
            self.stopped = false
            self.reportedLoss = false
            self.ready = false
            self.buffer.removeAll()
            self.pending.removeAll()
            self.pingTimer?.cancel()
            self.pingTimer = nil
            self.subscriptions = subscriptions
            self.connection?.cancel()

            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                self.emit("Failed: bad port")
                self.reportLoss()
                return
            }
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                self?.queue.async {
                    guard let self, self.generation == generation else { return }
                    self.handle(
                        state,
                        connection: connection,
                        clientID: clientID,
                        willTopic: willTopic
                    )
                }
            }
            connection.start(queue: self.queue)
            self.emit("Connecting to \(host)")
        }
    }

    func publish(topic: String, payload: Data, retain: Bool) {
        queue.async {
            guard self.ready, let connection = self.connection else {
                self.pending.removeAll { $0.topic == topic && $0.retain == retain }
                self.pending.append((topic, payload, retain))
                return
            }
            self.send(MQTTCodec.publish(topic: topic, payload: payload, retain: retain), on: connection)
        }
    }

    /// Drops the socket without DISCONNECT so the broker publishes the last will.
    func stop() {
        queue.async {
            self.stopped = true
            self.ready = false
            self.pingTimer?.cancel()
            self.pingTimer = nil
            self.connection?.cancel()
            self.connection = nil
            self.emit("Disconnected")
        }
    }

    private func handle(
        _ state: NWConnection.State,
        connection: NWConnection,
        clientID: String,
        willTopic: String
    ) {
        switch state {
        case .ready:
            emit("Broker reachable")
            let packet = MQTTCodec.connect(
                clientID: clientID,
                keepAlive: keepAlive,
                willTopic: willTopic,
                willMessage: "offline"
            )
            send(packet, on: connection)
            receive(on: connection)
        case .waiting(let error):
            emit("Waiting: \(error.localizedDescription)")
        case .failed(let error):
            fail("Failed: \(error.localizedDescription)", connection: connection)
        case .cancelled:
            ready = false
            pingTimer?.cancel()
            pingTimer = nil
            if !stopped { reportLoss() }
        case .preparing:
            emit("Connecting…")
        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            self?.queue.async {
                guard let self, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    if self.buffer.count > 262_144 {
                        self.fail("Broker sent too much data", connection: connection)
                        return
                    }
                    let packets = MQTTCodec.takePackets(from: &self.buffer)
                    for packet in packets {
                        self.handle(packet, connection: connection)
                    }
                }
                if let error {
                    self.fail("Receive error: \(error.localizedDescription)", connection: connection)
                    return
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ packet: MQTTIncoming, connection: NWConnection) {
        switch packet {
        case .connack(let code):
            guard code == 0 else {
                fail("Broker refused connection (\(code))", connection: connection)
                return
            }
            ready = true
            send(MQTTCodec.subscribe(packetID: 1, topics: subscriptions), on: connection)
            startPing(on: connection)
            let queued = pending
            pending.removeAll()
            for item in queued {
                send(MQTTCodec.publish(topic: item.topic, payload: item.payload, retain: item.retain), on: connection)
            }
            emit("Connected")
            let readyCallback = onReady
            DispatchQueue.main.async { readyCallback?() }
        case .publish(let topic, let payload):
            let callback = onMessage
            DispatchQueue.main.async { callback?(topic, payload) }
        case .suback, .pingresp, .other:
            break
        }
    }

    private func startPing(on connection: NWConnection) {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            guard let self, self.ready else { return }
            self.send(MQTTCodec.pingreq(), on: connection)
        }
        timer.resume()
        pingTimer = timer
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.queue.async {
                guard self?.connection === connection else { return }
                self?.fail("Send error: \(error.localizedDescription)", connection: connection)
            }
        })
    }

    private func fail(_ text: String, connection: NWConnection) {
        ready = false
        pingTimer?.cancel()
        pingTimer = nil
        if self.connection === connection {
            self.connection = nil
        }
        connection.cancel()
        emit(text)
        reportLoss()
    }

    private func reportLoss() {
        guard !reportedLoss, !stopped else { return }
        reportedLoss = true
        let callback = onLost
        DispatchQueue.main.async { callback?() }
    }

    private func emit(_ text: String) {
        let callback = onState
        DispatchQueue.main.async { callback?(text) }
    }
}
