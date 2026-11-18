# Position MQTT specifications

Native SwiftUI app on a physical iPhone. Home-screen name: **Position MQTT**. Bundle id: `com.gregorycowley.positionMqtt`. Project: `position-mqtt.xcodeproj`.

How to install it on a phone: [README.md](README.md).

## Purpose

Tell the room which of four zones this phone is standing in, over MQTT. The room is CCA RM 140 actual: 7.747 m by 11.111 m, origin at the bottom-left. Four Kontakt beacons, one at the center of each zone. The published `(x, y)` is that beacon, not a laterated point between them.

This app is **not**:

- Beacon Position. That app estimates a continuous floor position and must not open MQTT.
- A GATT writer.
- A reader of the phone’s hardware MAC. iOS does not provide it. The operator pastes the Wi-Fi address, and that string is the phone’s identity on the broker.

## Requirements

### Broker

- Host `pi02zigbee.lan`, port **1883**, MQTT 3.1.1, no username or password.
- Topic prefix `/cca/r140/iphone/`, including the leading slash.
- Position topic: `/cca/r140/iphone/{MAC}/position`
- Status topic: `/cca/r140/iphone/{MAC}/status`, retained `online`, last will retained `offline` if the socket drops without a disconnect.
- Config topics: `/cca/r140/iphone/config` for every phone, and `/cca/r140/iphone/{MAC}/config` for one phone.
- `{MAC}` is uppercase colon form, `AA:BB:CC:DD:EE:FF`. Client id is `iphone-` plus the twelve hex digits.

### Identity

- The MAC is typed once and stored on the phone. The app does not connect until it is valid.
- A shared config message that includes `mac` applies only to that phone. A `mac` value that is not a MAC is ignored, so a typo does not change every handset.
- The same MAC is inside the default JSON body, so a copied message still names the phone.

### Zones

Inventory is the 2026-11-06 CCA RM 140 actual site, compiled into the app. UUID `F7826DA6-4FA2-4E98-8024-BC5B71E0893E`. iPhone `tx1m` from that capture.

| Zone | Major / minor | Center (m) | tx1m |
|---|---|---|---|
| K01 | 32268 / 3719 | 1.723, 4.155 | −49 |
| K02 | 11616 / 20716 | 1.723, 9.077 | −56 |
| K03 | 35436 / 14422 | 5.069, 9.077 | −50 |
| K04 | 87 / 15933 | 5.069, 4.155 | −48 |

- Range that UUID with CoreLocation. Match factory major and minor. Drop RSSI 0.
- Slant uses path-loss **n = 3**: `10 ^ ((tx1m − rssi) / 30)`, after an EMA (`α = 0.32`). The nearest slant is the zone. Raw RSSI would favor K04, whose 1 m reading is louder.
- Stay in the current zone until another beacon is closer by `hysteresis_m` (default 0.4). If the current beacon goes silent, switch immediately.
- One heard beacon is enough. None means publish nothing.

### Position body

Default `json`:

```json
{"mac":"AA:BB:CC:DD:EE:FF","x":1.827,"y":4.504,"region":"K01"}
```

`format` selects `xy` (`1.827,4.504`), `region` (`K01`), or `xy_region` (`1.827,4.504,K01`). Metres are three decimal places, POSIX decimal point.

Send at once when the zone changes. Repeat the same zone every `interval_s` (default 1, clamped 0.2–30). `enabled: false` keeps the session and stops position messages.

### Config body

JSON object on either config topic.

| Key | Effect |
|---|---|
| `interval_s` or `interval` | Repeat period |
| `format` | `json`, `xy`, `region`, `xy_region` |
| `enabled` | Broadcast on or off |
| `hysteresis_m` or `hysteresis` | Switch margin, clamped 0–5 m |
| `mac` | Shared topic only: target phone |

Settings are stored on the phone and kept across launches.

### Host

- iPhone. Deployment target **17.0**. Sign the app with your own Apple ID.
- **Location When In Use** for ranging. **Local Network** for the broker. No Bluetooth permission: ranging goes through CoreLocation.
- Foreground only.

### Floor plan

- `room.html` is the room display, served beside the app. It is not part of the iOS binary.
- `python3 serve.py` listens on port **8768**, subscribes to `/cca/r140/iphone/#` on `pi02zigbee.lan:1883`, and relays publishes to the page. A browser cannot open port 1883 itself.
- The plan is the same room: 7.747 m by 11.111 m, origin bottom-left, one cell per beacon. The marker is the published `(x, y)`. A `region` body with no coordinates uses that beacon’s center.
- Every phone on the prefix is shown. Phones that share a zone are drawn apart so one does not hide another.
- `room.html?ws=ws://host:port` talks MQTT over WebSocket directly and does not use the relay.

### What this app must not do

- Laterate a continuous point, or pretend the published coordinate is the phone rather than the zone center.
- Write GATT, or change Kontakt UUID, major, or minor.
- Read or invent a hardware MAC.
- Talk to position-server or the HiveMQ calibration broker.

## Abilities

| Ability | How |
|---|---|
| Identify the phone | Pasted Wi-Fi MAC, used in the client id, topics, and JSON |
| Choose a zone | Nearest of K01–K04 by slant |
| Publish the zone | MQTT position topic, `(x, y)` and/or region |
| Receive configuration | Subscribe to the shared and per-phone config topics |
| Show the room | Four cells, beacon dot at each center |
| Reconnect | Retry the broker 3 s after a dropped session |
| Show phones on a room screen | `room.html` via `serve.py` |

## Success

1. With a pasted MAC, the phone connects to `pi02zigbee.lan:1883` and subscribes to both config topics.
2. Standing nearest one Kontakt, `/cca/r140/iphone/{MAC}/position` carries that zone’s id and that beacon’s `x,y`.
3. A config message with `format` `region` changes the next body to `K01` (or whichever zone is current) without a rebuild.
4. A shared config whose `mac` is a different phone does not change this one.
