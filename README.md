# Position MQTT

iPhone app for CCA Room 140. It hears the four Kontakt beacons, picks the zone you are standing in, and publishes that zone to the room broker at `pi02zigbee.lan`.

The app needs **iOS 17** and a Mac with **Xcode** to install. An iPhone cannot install it from the GitHub download alone.

## Put it on your phone

1. Install Xcode from the Mac App Store.
2. Clone this repo and open `position-mqtt.xcodeproj`.
3. Plug in your iPhone and tap Trust on the phone.
4. In Xcode, select the **position-mqtt** target, open **Signing & Capabilities**, and choose your Apple ID under Team. Xcode will create a free personal team if you sign in with an Apple ID.
5. If Xcode says the bundle id is unavailable, change it to `com.<yourname>.positionMqtt`.
6. Choose your iPhone as the run destination and press Run.
7. On the phone, if iOS blocks the app: **Settings → General → VPN & Device Management**, and trust your developer certificate.
8. Allow **Location** and **Local Network**.
9. Join the room Wi-Fi, the same network as `pi02zigbee.lan`.
10. Copy **Settings → General → About → Wi-Fi Address**, paste it into the app, and tap **Use this MAC**. The broker uses that address to tell the phones apart. iOS does not let the app read it.

A free Apple ID install lasts about 7 days. Run it from Xcode again to renew.

## What it sends

The broker is `pi02zigbee.lan`, port **1883**, with no username. Topic prefix: `/cca/r140/iphone/`.

| Topic | Body |
|---|---|
| `/cca/r140/iphone/{MAC}/position` | zone, as JSON by default |
| `/cca/r140/iphone/{MAC}/status` | `online`, or `offline` if the phone disconnects |

`{MAC}` is the Wi-Fi address you pasted, uppercase, with colons.

Default position body:

```json
{"mac":"AA:BB:CC:DD:EE:FF","x":1.827,"y":4.504,"region":"K01"}
```

`region` is `K01`, `K02`, `K03`, or `K04`. `x` and `y` are the beacon at the center of that zone, in metres from the bottom-left of the room.

Details: [SPECS.md](SPECS.md).
