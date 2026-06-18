# WhoopSDK

Comprehensive Swift SDK for interacting with WHOOP devices and the official WHOOP cloud API.

## Modules

| Module | Purpose |
|--------|---------|
| `WhoopProtocol` | Pure Swift BLE protocol decoder — framing, CRC, commands, IMU/optical decode. No CoreBluetooth. |
| `WhoopBLE` | CoreBluetooth client for WHOOP 4.0 and 5.0 straps. |
| `WhoopAPI` | Official WHOOP REST API v2 client with OAuth2. |
| `WhoopSDK` | Umbrella module re-exporting all capabilities. |

## Capabilities

### BLE (direct strap)

- WHOOP 4.0 and 5.0 (puffin) protocol support
- Bonding, auto-reconnect, FAL pairing-mode error handling
- Live heart rate and R-R intervals (custom + standard 0x2A37)
- Battery level and extended battery info
- Historical data offload with trim-cursor ACK
- Raw IMU (accelerometer + gyroscope) decode
- Raw optical/PPG packet capture
- Strap events (wrist on/off, charging, bonding, etc.)
- Research commands: raw data, IMU mode, optical config

### REST API (cloud)

- OAuth2 authorization and token refresh
- User profile and body measurements
- Cycles, sleep, recovery, workouts (paginated + fetch-all)
- Activity ID mapping (v1 → v2)
- Token revocation

## Open-source sources

Full community audit (repos surveyed, consensus, haptics, alarms): **[docs/whoop-open-source-reference.md](../docs/whoop-open-source-reference.md)**

This SDK synthesizes reverse-engineering and API work from the community:

| Project | Contribution |
|---------|-------------|
| [NoopApp/noop](https://github.com/NoopApp/noop) | WHOOP 4.0 + 5.0 BLE protocol, framing, handshake ordering |
| [johnmiddleton12/my-whoop](https://github.com/johnmiddleton12/my-whoop) | WHOOP 4.0 protocol, IMU/optical raw decode offsets |
| [b-nnett/goose](https://github.com/b-nnett/goose) | WHOOP 5.0 puffin protocol, CLIENT_HELLO |
| [jogolden/whoomp](https://github.com/jogolden/whoomp) | Frame format, command enum, event numbers |
| [felixnext/whoopy](https://github.com/felixnext/whoopy) | WHOOP API v2 client design and models |
| [gabrielmbmb/whoop-client](https://github.com/gabrielmbmb/whoop-client) | API endpoint coverage |
| [developer.whoop.com](https://developer.whoop.com/) | Official OpenAPI spec and OAuth scopes |

**Not affiliated with WHOOP.** This is an independent interoperability SDK for your own device and data.

## Usage

```swift
import WhoopSDK

// BLE — direct strap
let ble = WhoopSDK.makeBLEClient(family: .whoop4)
ble.onSamples = { batch in /* upload or persist */ }
ble.connect()

// REST API — cloud data
let token = try await WhoopOAuth.exchangeCode(code: "...", clientID: "...", clientSecret: "...", redirectURI: "...")
let api = WhoopSDK.makeAPIClient(token: token, clientID: "...", clientSecret: "...")
let recoveries = try await api.getAllRecoveries()
```
