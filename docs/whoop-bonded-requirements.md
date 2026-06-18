# WHOOP bonded-strap requirements

This document lists every WHOOP strap capability and whether it requires a **bonded** BLE link (encrypted custom GATT service). It is the authoritative checklist for `WhoopSDK` and the Aceso iOS app.

For protocol background see [whoop-open-source-reference.md](./whoop-open-source-reference.md).

---

## What “bonded” means

| Generation | Bond initiation | `WhoopBLEClient.isBonded` becomes `true` when |
|---|---|---|
| WHOOP 4.0 | First **write-with-response** to the custom command char (SDK uses `GET_BATTERY_LEVEL` / opcode 26) | Command write ACKs without encryption error |
| WHOOP 5.0 | Static 16-byte `CLIENT_HELLO` write-with-response | `CLIENT_HELLO` ACK, or standard HR notify arrives before puffin notify subscription |

**Bond is not the same as “connected”.** `connectionState == .connected` only means the GATT link is up and the post-bond handshake ran. Standard heart rate (`0x2A37`) can flow before bond on both generations.

**Filter Accept List (FAL):** WHOOP 4.0 only accepts L2CAP from previously bonded phone addresses. If scan finds the strap but connect never completes, the user must enter pairing mode (repeatedly tap the sensor side) and tap Retry.

---

## Capability matrix

| Capability | `WhoopCapability` | Bond required | SDK entry point | Notes |
|---|---|:---:|---|---|
| Live HR (standard SIG) | `liveHeartRateStandard` | No | `0x2A37` notify on service `180D` | Works pre-bond; 5.0 can trigger bond detection via this char |
| Battery (standard SIG) | `batteryStandard` | No | `0x2A19` read/notify on service `180F` | 5.0 battery % available here pre-bond |
| Live HR (custom protocol) | `liveHeartRateCustom` | **Yes** | Type-40 realtime frames on custom notify chars | Requires custom notify subscription (post-bond on 5.0) |
| Battery (custom protocol) | `batteryCustom` | **Yes** | Opcode 26 / 98 responses | 4.0 bond-init write; extended info via opcode 98 |
| Set strap clock | `setClock` | **Yes** | Auto on bond: `WhoopCommand.setClock` | **Required** before historical offload; 8-byte epoch+subsec payload |
| Historical data offload | `historicalOffload` | **Yes** | Auto on bond: `sendHistoricalData` | Type-47 packets + metadata 49/56; trim ACK via opcode 23 |
| Version / firmware info | `versionInfo` | **Yes** | `requestVersionInfo()` / `versionInfo` property | Opcode 7 |
| Stored data window | `dataRange` | **Yes** | `requestDataRange()` / `dataRange` property | Opcode 34 |
| Strap events | `strapEvents` | **Yes** | `onEvent` callback | Wrist on/off, charging, alarm fired, haptics fired, etc. |
| Console logs | `consoleLogs` | **Yes** | `onConsoleLog` callback | Type-50 frames; firmware debug strings |
| Haptics (vibration) | `haptics` | **Yes** | `runHaptics()`, `stopHaptics()`, `requestHapticsPatterns()` | 4.0: opcode 79; 5.0: opcode **19** (79 rejected) |
| Alarms (RTC-scheduled buzz) | `alarms` | **Yes** | `setAlarm()`, `getAlarm()`, `runAlarm()`, `disableAlarm()` | Opcodes 66–69; single alarm slot; 5.0 **experimental** |
| Raw IMU stream | `rawIMU` | **Yes** | `startRawData()` → `onRawIMU` | Opcodes 81/82, 105/106 |
| Raw optical / PPG | `rawOptical` | **Yes** | `startRawData()` → `onRawOptical` | Opcodes 81/82, 107 |

---

## Commands that require bond

All commands below are sent as type-35 frames on the custom command characteristic. They are silently ignored or rejected without bond.

### Auto-sent on bond (SDK handshake)

| Opcode | Name | Purpose |
|---:|---|---|
| 10 | `SET_CLOCK` | Sync RTC — prerequisite for history and alarms |
| 3 | `TOGGLE_REALTIME_HR` | Enable custom HR stream (5.0 only in handshake) |
| 63 | `SEND_R10_R11_REALTIME` | Raw flood control |
| 34 | `GET_DATA_RANGE` | Oldest/newest stored timestamps |
| 7 | `REPORT_VERSION_INFO` | Firmware strings |
| 22 | `SEND_HISTORICAL_DATA` | Start historical offload |

### Haptics (bonded)

| Opcode | Name | 4.0 | 5.0 |
|---:|---|---|---|
| 79 | `RUN_HAPTICS_PATTERN` | ✅ `[patternId, loops, 0, 0, 0]` | ❌ rejected |
| 19 | `RUN_HAPTIC_PATTERN_MAVERICK` | — | ✅ 12-byte DRV2625 payload |
| 122 | `STOP_HAPTICS` | ✅ | ✅ |
| 80 | `GET_ALL_HAPTICS_PATTERN` | ✅ | unknown layout |

SDK helpers: `WhoopHapticPattern4`, `WhoopHapticPreset5`, `WhoopHaptics`.

### Alarms (bonded; 5.0 experimental)

| Opcode | Name | Payload |
|---:|---|---|
| 66 | `SET_ALARM_TIME` | `[0x01][epoch u32 LE][0x00][0x00]` |
| 67 | `GET_ALARM_TIME` | `[0x01]` |
| 68 | `RUN_ALARM` | `[0x01]` |
| 69 | `DISABLE_ALARM` | `[0x01]` |

The strap holds **one** alarm slot. Valid RTC (via `SET_CLOCK`) is required.

### Research / sensors (bonded)

| Opcode | Name | SDK method |
|---:|---|---|
| 81 | `START_RAW_DATA` | `startRawData()` |
| 82 | `STOP_RAW_DATA` | `stopRawData()` |
| 106 | `TOGGLE_IMU_MODE` | `startRawData()` / `stopRawData()` |
| 107 | `ENABLE_OPTICAL_DATA` | `startRawData()` |
| 98 | `GET_EXTENDED_BATTERY_INFO` | `requestExtendedBattery()` |

---

## Notify channels that require bond

| Channel | Packet types | Bond |
|---|---|:---:|
| Custom notify `…0003` | Command responses (36/38) | **Yes** |
| Custom notify `…0004` | Events (48), console (50) | **Yes** |
| Custom notify `…0005` | Realtime (40), historical (47), raw (43) | **Yes** |
| Custom notify `…0007` (5.0) | Additional puffin stream | **Yes** |
| Standard HR `2A37` | SIG heart rate | No |
| Standard battery `2A19` | SIG battery level | No |

---

## Events only visible after bond

These `WhoopEventNumber` values arrive on bonded custom notify channels:

| Event | Number | Meaning |
|---|---:|---|
| `bleBonded` | 23 | Strap acknowledges bond |
| `wristOn` / `wristOff` | 9 / 10 | Wear detection |
| `chargingOn` / `chargingOff` | 7 / 8 | Charger state |
| `strapDrivenAlarmSet` | 56 | Firmware alarm armed |
| `strapDrivenAlarmExecuted` | 57 | Firmware alarm fired |
| `appDrivenAlarmExecuted` | 58 | `RUN_ALARM` test fired |
| `strapDrivenAlarmDisabled` | 59 | Alarm dismissed |
| `hapticsFired` | 60 | Haptic played |
| `hapticsTerminated` | 100 | Haptic stopped early |
| `rawDataCollectionOn` / `Off` | 46 / 47 | Raw mode state |
| `highFreqSyncPrompt` / `Enabled` / `Disabled` | 96–98 | High-frequency sync mode |

---

## What works without bond

Useful for connection UI before the user completes pairing:

- Scan and connect to the custom service (link comes up)
- Standard heart rate from `0x2A37` (may be the only live metric pre-bond on 5.0)
- Standard battery read on 5.0
- Detecting that bond failed (`connectionError` with pairing-mode instructions)

**Does not work without bond:** haptics, alarms, historical sync, custom HR/RR, events, raw sensors, clock set, version info, data range.

---

## Cloud REST API

The official WHOOP REST API (`WhoopAPI` module) is **unrelated to BLE bonding**. It uses OAuth2 and talks to `api.prod.whoop.com`. No strap bond required.

---

## Related files

| File | Role |
|---|---|
| `packages/whoop-sdk/Sources/WhoopProtocol/whoop-packet-types.swift` | `WhoopCapability`, `WhoopBondRequirement` enums |
| `packages/whoop-sdk/Sources/WhoopProtocol/whoop-haptics.swift` | Haptic payload builders |
| `packages/whoop-sdk/Sources/WhoopBLE/whoop-ble-client.swift` | `isBonded`, bonded-only methods |
| `docs/whoop-bonded-integration-guide.md` | Step-by-step wiring guide for Aceso when bond is active |
