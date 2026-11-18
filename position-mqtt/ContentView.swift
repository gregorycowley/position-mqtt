import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    liveCard
                    mapCard
                    readingCard
                    identityCard
                    brokerCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Position MQTT")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(FieldInk.color)
        .task { model.start() }
    }

    private var liveCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.activeZoneID ?? "Listening")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.activeZoneID == nil ? Color.secondary : FieldInk.color)
                if let place = model.activePlace {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(coordinateLine)
                    .font(.system(.title3, design: .monospaced))
                Text(model.lastPayload.isEmpty ? "Nothing sent yet" : model.lastPayload)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var mapCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("CCA RM 140")
                    .font(.headline)
                Text("Each dot is the beacon at the center of its zone. The published point is that dot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                RoomMap(room: model.room, activeZoneID: model.activeZoneID)
            }
        }
    }

    private var readingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.locationStatus)
                    .font(.headline)
                ForEach(model.readings) { reading in
                    HStack {
                        Text(reading.id)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(reading.id == model.activeZoneID ? FieldInk.color : Color.primary)
                        Text(reading.place)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(readingLine(reading))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var identityCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("This phone")
                    .font(.headline)
                Text("iOS cannot read the Wi-Fi address. Copy it from Settings → General → About → Wi-Fi Address. Topics and messages use that MAC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("AA:BB:CC:DD:EE:FF", text: $model.macDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { model.commitMAC() }
                if let macError = model.macError {
                    Text(macError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("Use this MAC") { model.commitMAC() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var brokerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Broker.host):\(Broker.port)")
                    .font(.system(.body, design: .monospaced))
                Text(model.mqttStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.configNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Broadcast", isOn: Binding(
                    get: { model.config.enabled },
                    set: { model.setEnabled($0) }
                ))
                Text("\(model.config.format.rawValue) · every \(intervalLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let mac = model.committedMAC {
                    Text(Topics.position(mac))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(Topics.deviceConfig(mac))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var coordinateLine: String {
        guard let x = model.activeX, let y = model.activeY else { return "x —, y —" }
        return "x \(PositionPayload.meters(x)), y \(PositionPayload.meters(y))"
    }

    private var intervalLabel: String {
        let interval = model.config.interval
        if interval.rounded() == interval { return "\(Int(interval))s" }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), interval) + "s"
    }

    private func readingLine(_ reading: ZoneReading) -> String {
        guard let rssi = reading.rssi, let slant = reading.slant else { return "—" }
        return "\(Int(rssi.rounded())) dBm · \(PositionPayload.meters(slant)) m"
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
